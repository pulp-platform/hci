#!/usr/bin/env python3
"""Plot sweep metrics from parsed transcript JSON files."""

import argparse
import json
import math
import re
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import ListedColormap
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

INTERCO_ORDER = {"LOG": 0, "HCI": 1, "MUX": 2}
INTERCO_COLORS = {"LOG": "#1f77b4", "MUX": "#9467bd", "HCI": "#ff7f0e"}
IDEAL_COLOR = "#7f7f7f"
IDEAL_RED = "#C0392B"   # rich crimson for ideal-workload lines and annotations

# Colors for invert_prio=0 (blue) and invert_prio=1 (orange)
TB_INVERT_COLORS = {0: "#2196F3", 1: "#FF9800", None: "#78909C"}


def _to_int(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def _to_float(value: object, default: float = float("nan")) -> float:
    try:
        return float(value)
    except Exception:
        return default


def _master_sort_key(master: str) -> Tuple[int, int]:
    if master.startswith("master_log_"):
        return (0, int(master.rsplit("_", 1)[1]))
    if master.startswith("master_hwpe_"):
        return (1, int(master.rsplit("_", 1)[1]))
    return (9, 0)


def _parse_hw_cfg_from_filename(path: Path) -> Tuple[str, int, int]:
    """Parse (interco_type, n_hwpe, hwpe_width_fact) from filename stem.

    Handles both old-style 'hardware_X_Nhwpe_Mfact.json' and new combined
    'hardware_X_Nhwpe_Mfact_testbench_*.json' names.
    """
    match = re.match(r"^hardware_([a-zA-Z]+)_([0-9]+)hwpe_([0-9]+)fact", path.stem)
    if not match:
        return ("UNK", 0, 0)
    return (match.group(1).upper(), int(match.group(2)), int(match.group(3)))


# Keep the old name as an alias so callers that still use it don't break.
_parse_cfg_from_filename = _parse_hw_cfg_from_filename


def _parse_tb_cfg_from_stem(stem: str) -> Tuple[Optional[int], Optional[int], Optional[int], str]:
    """Parse TB config embedded in a combined result filename stem.

    Returns (invert_prio, stall_num, stall_den, tb_name).
    All values are None / '' when no testbench segment is found.
    """
    match = re.search(r"(testbench_invert_([01])_stall_([0-9]+)_([0-9]+))", stem)
    if not match:
        return (None, None, None, "")
    return (int(match.group(2)), int(match.group(3)), int(match.group(4)), match.group(1))


def _tb_sort_key(entry: Dict) -> Tuple:
    stall_num = entry.get("stall_num") or 0
    stall_den = entry.get("stall_den") or 1
    invert = entry.get("invert_prio") if entry.get("invert_prio") is not None else -1
    return (invert, stall_num / stall_den)


def _derive_interco_side(hw_cfg: Dict[str, object]) -> Dict[str, int]:
    masters = hw_cfg.get("masters", {}) if isinstance(hw_cfg, dict) else {}
    memory = hw_cfg.get("memory", {}) if isinstance(hw_cfg, dict) else {}
    interco_side = hw_cfg.get("interconnect_side", {}) if isinstance(hw_cfg, dict) else {}

    if isinstance(interco_side, dict) and "narrow_total_ports" in interco_side:
        return {
            "n_narrow_hci": _to_int(interco_side.get("n_narrow_hci")),
            "n_wide_hci": _to_int(interco_side.get("n_wide_hci")),
            "n_dma": _to_int(interco_side.get("n_dma")),
            "n_ext": _to_int(interco_side.get("n_ext")),
            "narrow_total_ports": _to_int(interco_side.get("narrow_total_ports")),
            "total_initiator_ports": _to_int(interco_side.get("total_initiator_ports")),
        }

    interco_type = str(interco_side.get("type", "UNK")).upper()
    if interco_type == "UNK":
        interco_type = str(hw_cfg.get("interco_type", "UNK")).upper()

    n_core = _to_int(masters.get("core"))
    n_dma = _to_int(masters.get("dma"))
    n_ext = _to_int(masters.get("ext"))
    n_hwpe = _to_int(masters.get("hwpe"))
    hwpe_width = _to_int(memory.get("hwpe_width_lanes"), 1)

    if interco_type == "LOG":
        n_narrow_hci = n_core + n_hwpe * hwpe_width
        n_wide_hci = 0
    elif interco_type == "MUX":
        n_narrow_hci = n_core
        n_wide_hci = 1 if n_hwpe > 0 else 0
    else:
        n_narrow_hci = n_core
        n_wide_hci = n_hwpe

    narrow_total = n_narrow_hci + n_dma + n_ext
    return {
        "n_narrow_hci": n_narrow_hci,
        "n_wide_hci": n_wide_hci,
        "n_dma": n_dma,
        "n_ext": n_ext,
        "narrow_total_ports": narrow_total,
        "total_initiator_ports": narrow_total + n_wide_hci,
    }


def _load_results(results_dir: Path) -> List[Dict[str, object]]:
    entries: List[Dict[str, object]] = []
    for path in sorted(results_dir.glob("hardware_*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue

        hw_cfg = data.get("hw_config", {})
        masters = hw_cfg.get("masters", {}) if isinstance(hw_cfg, dict) else {}
        memory = hw_cfg.get("memory", {}) if isinstance(hw_cfg, dict) else {}
        bw = data.get("bandwidth", {})

        interco_from_name, n_hwpe_name, wf_name = _parse_hw_cfg_from_filename(path)
        interco_type = str(hw_cfg.get("interconnect_side", {}).get("type", interco_from_name)).upper()
        if interco_type not in INTERCO_ORDER:
            interco_type = interco_from_name

        n_hwpe = _to_int(masters.get("hwpe"), n_hwpe_name)
        n_core = _to_int(masters.get("core"))
        hwpe_wf = _to_int(memory.get("hwpe_width_lanes"), wf_name)
        cfg_label = f"{interco_type}_{n_hwpe}x{hwpe_wf}"

        interco_side = _derive_interco_side(hw_cfg if isinstance(hw_cfg, dict) else {})
        banks = _to_int(memory.get("banks"))
        data_width = _to_int(memory.get("data_width_bits"))
        ideal_mem = float(banks * data_width)
        ideal_interco = float(
            interco_side["narrow_total_ports"] * data_width
            + interco_side["n_wide_hci"] * hwpe_wf * data_width
        )
        ideal_bottleneck = min(ideal_mem, ideal_interco)

        actual_bw = _to_float(bw.get("actual_completion_bit_per_cycle"))
        util_pct = (actual_bw / ideal_bottleneck * 100.0) if ideal_bottleneck > 0 and not math.isnan(actual_bw) else float("nan")

        invert_prio, stall_num, stall_den, tb_name = _parse_tb_cfg_from_stem(path.stem)
        # Full hardware config name: strip the testbench suffix from the stem
        hw_name = path.stem[: path.stem.index(f"_{tb_name}")] if tb_name else path.stem

        entries.append(
            {
                "path": path,
                "label": cfg_label,
                "hw_name": hw_name,
                "interco_type": interco_type,
                "n_hwpe": n_hwpe,
                "hwpe_width_fact": hwpe_wf,
                "json": data,
                "total_sim_cycles": _to_float(data.get("simulation_time", {}).get("total_cycles")),
                "avg_req_to_gnt_per_master": data.get("request_to_grant_latency", {}).get("per_master", []),
                "ideal_mem_bw": ideal_mem,
                "ideal_interco_bw": ideal_interco,
                "ideal_bottleneck_bw": ideal_bottleneck,
                "actual_bw": actual_bw,
                "utilization_pct": util_pct,
                "n_core": n_core,
                # TB config fields
                "tb_name": tb_name,
                "invert_prio": invert_prio,
                "stall_num": stall_num,
                "stall_den": stall_den,
            }
        )

    entries.sort(key=lambda e: (e["n_hwpe"], e["hwpe_width_fact"], INTERCO_ORDER.get(e["interco_type"], 9)))
    return entries


def _parse_ideal_runtime(ideal_json_path: Path) -> float:
    if not ideal_json_path:
        return None
    if not ideal_json_path.is_file():
        print(f"Warning: Ideal run JSON file not found at: {ideal_json_path}. Skipping ideal runtime comparison.")
        raise SystemExit(f"Ideal run JSON file not found: {ideal_json_path}")
    try:
        data = json.loads(ideal_json_path.read_text(encoding="utf-8"))
        ideal_runtime = _to_float(data.get("simulation_time", {}).get("total_cycles"))
        if math.isnan(ideal_runtime) or ideal_runtime <= 0.0:
            print(f"Error: Invalid ideal runtime value in JSON file: {ideal_json_path}. Value: {ideal_runtime}.")
            raise ValueError(f"Invalid ideal runtime value: {ideal_runtime}")
        return ideal_runtime
    except Exception as e:
        print(f"Error: Failed to parse ideal runtime from JSON file: {ideal_json_path}. Exception: {e}")
        raise SystemExit(f"Failed to parse ideal runtime from JSON file: {ideal_json_path}")


# -----------------------------------------------------------------------
# Tick-label helpers
# -----------------------------------------------------------------------

def _apply_interco_tick_labels(ax, x_positions, entries) -> None:
    """Three-line x-tick labels: INTERCO_TYPE / N cores / M HWPEs."""
    ax.set_xticks(x_positions)
    ax.set_xticklabels([""] * len(entries))
    for xi, entry in zip(x_positions, entries):
        ax.annotate(
            entry["interco_type"],
            xy=(xi, 0), xycoords=("data", "axes fraction"),
            xytext=(0, -5), textcoords="offset points",
            ha="center", va="top", fontsize=10,
        )
        ax.annotate(
            f"{entry['n_core']} cores",
            xy=(xi, 0), xycoords=("data", "axes fraction"),
            xytext=(0, -18), textcoords="offset points",
            ha="center", va="top", fontsize=8,
        )
        ax.annotate(
            f"{entry['n_hwpe']} HWPEs",
            xy=(xi, 0), xycoords=("data", "axes fraction"),
            xytext=(0, -29), textcoords="offset points",
            ha="center", va="top", fontsize=8,
        )


def _apply_tb_tick_labels(ax, x_positions, entries) -> None:
    """Two-line x-tick labels for TB sweep: stall ratio / invert prio."""
    ax.set_xticks(x_positions)
    ax.set_xticklabels([""] * len(entries))
    for xi, entry in zip(x_positions, entries):
        stall_num = entry.get("stall_num")
        stall_den = entry.get("stall_den")
        invert = entry.get("invert_prio")
        stall_str = f"{stall_num}/{stall_den}" if stall_num is not None else "?"
        inv_str = f"inv={'on' if invert else 'off'}" if invert is not None else ""
        ax.annotate(
            stall_str,
            xy=(xi, 0), xycoords=("data", "axes fraction"),
            xytext=(0, -5), textcoords="offset points",
            ha="center", va="top", fontsize=10,
        )
        ax.annotate(
            inv_str,
            xy=(xi, 0), xycoords=("data", "axes fraction"),
            xytext=(0, -18), textcoords="offset points",
            ha="center", va="top", fontsize=8,
        )


# -----------------------------------------------------------------------
# Per-TB plots (fixed TB, sweep HW) — same metrics as before
# -----------------------------------------------------------------------

def _set_title(ax, title: str, subtitle: str = "") -> None:
    """Set a bold main title with an optional smaller subtitle below it."""
    ax.set_title(title, fontweight="bold", pad=24 if subtitle else 6)
    if subtitle:
        ax.annotate(
            subtitle,
            xy=(0.5, 1.0), xycoords="axes fraction",
            xytext=(0, 4), textcoords="offset points",
            ha="center", va="bottom",
            fontsize=8, color="#555555",
            annotation_clip=False,
        )

def _plot_total_sim_time(entries: List[Dict[str, object]], ideal_runtime: float, out_path: Path, subtitle: str = "") -> None:
    values = [e["total_sim_cycles"] for e in entries]
    colors = [INTERCO_COLORS.get(e["interco_type"], "#333333") for e in entries]
    x = np.arange(len(entries), dtype=float)

    fig, ax = plt.subplots(figsize=(max(8, 1.2 * len(entries)), 5.6))
    bars = ax.bar(x, values, color=colors, width=0.68)
    _set_title(ax, "Total simulation time vs ideal workload runtime", subtitle)
    ax.set_ylabel("cycles")
    ax.set_xlabel("Configuration", labelpad=50)
    _apply_interco_tick_labels(ax, x, entries)
    ax.set_axisbelow(True)
    ax.grid(axis="y", alpha=0.25)

    for bar, val in zip(bars, values):
        if math.isnan(val):
            continue
        bar_cx = bar.get_x() + bar.get_width() / 2.0
        # Value on top of bar; × of ideal stacked just above it
        ax.text(bar_cx, val, f"{val:.0f} cyc", ha="center", va="bottom", fontsize=8)
        if ideal_runtime is not None and ideal_runtime > 0:
            mult_of_ideal = val / ideal_runtime
            ax.annotate(
                f"{mult_of_ideal:.2f}× of ideal",
                xy=(bar_cx, val), xytext=(0, 16),
                textcoords="offset points",
                ha="center", va="bottom", fontsize=7, color=IDEAL_RED, zorder=8,
                bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.75, edgecolor=IDEAL_RED, linewidth=0.8),
            )

    if ideal_runtime is not None:
        ax.axhline(y=ideal_runtime, color=IDEAL_RED, linestyle="--", linewidth=1.6)
        ax.text(
            0.98, ideal_runtime,
            f"ideal workload runtime: {ideal_runtime:.0f} cyc",
            transform=ax.get_yaxis_transform(),
            ha="right", va="center",
            fontsize=7.5, color=IDEAL_RED, zorder=6,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.97, edgecolor=IDEAL_RED, linewidth=0.8),
        )
    ax.margins(y=0.24)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def _plot_per_master_avg_req_to_gnt(
    entries: List[Dict[str, object]],
    out_path: Path,
    tick_label_fn: Callable = None,
    title_suffix: str = "",
    subtitle: str = "",
) -> None:
    if tick_label_fn is None:
        tick_label_fn = _apply_interco_tick_labels

    masters = sorted(
        {
            row.get("master_name", "")
            for e in entries
            for row in e.get("avg_req_to_gnt_per_master", [])
            if isinstance(row, dict) and row.get("master_name", "")
        },
        key=_master_sort_key,
    )

    if not masters:
        fig, ax = plt.subplots(figsize=(8, 3))
        ax.text(0.5, 0.5, "No per-master req->gnt data", ha="center", va="center")
        ax.axis("off")
        fig.tight_layout()
        fig.savefig(out_path, dpi=150)
        plt.close(fig)
        return

    matrix = np.full((len(masters), len(entries)), np.nan, dtype=float)
    master_idx = {m: i for i, m in enumerate(masters)}
    for j, entry in enumerate(entries):
        for row in entry.get("avg_req_to_gnt_per_master", []):
            if not isinstance(row, dict):
                continue
            m = row.get("master_name", "")
            if m not in master_idx:
                continue
            matrix[master_idx[m], j] = _to_float(row.get("avg_req_to_gnt_stall_latency_cycles"))

    cmap = ListedColormap(plt.cm.get_cmap("viridis")(np.linspace(0.0, 1.0, 256)))
    cmap.set_bad(color="white")

    fig, ax = plt.subplots(figsize=(max(10, 1.2 * len(entries)), max(4, 0.35 * len(masters))))
    im = ax.imshow(np.ma.masked_invalid(matrix), aspect="auto", cmap=cmap, interpolation="nearest")
    _set_title(ax, f"Avg req->gnt stall latency per master{title_suffix}", subtitle)
    ax.set_xlabel("Configuration", labelpad=50)
    ax.set_ylabel("Master")
    tick_label_fn(ax, np.arange(len(entries), dtype=float), entries)
    ax.set_yticks(np.arange(len(masters)))
    ax.set_yticklabels(masters)

    vmax = np.nanmax(matrix) if np.any(~np.isnan(matrix)) else 0.0
    thresh = 0.6 * vmax if vmax > 0 else 0.0
    for r in range(matrix.shape[0]):
        for c in range(matrix.shape[1]):
            val = matrix[r, c]
            if math.isnan(val):
                continue
            color = "white" if val < thresh else "black"
            ax.text(c, r, f"{val:.2f}", ha="center", va="center", fontsize=6, color=color)

    fig.colorbar(im, ax=ax, label="cycles")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def _plot_bandwidth(entries: List[Dict[str, object]], ideal_runtime: float, out_path: Path, subtitle: str = "") -> None:
    actual_vals = [e["actual_bw"] for e in entries]
    ideal_bottleneck_vals = [e["ideal_bottleneck_bw"] for e in entries]
    interco_util_vals = [e["utilization_pct"] for e in entries]
    sim_cycles_vals = [e["total_sim_cycles"] for e in entries]
    ideal_app_vals = []
    for actual_bw, sim_cycles in zip(actual_vals, sim_cycles_vals):
        if ideal_runtime is None or math.isnan(actual_bw) or math.isnan(sim_cycles) or ideal_runtime <= 0.0:
            ideal_app_vals.append(float("nan"))
        else:
            ideal_app_vals.append(actual_bw * sim_cycles / ideal_runtime)
    # Utilization w.r.t. ideal workload bandwidth: actual_bw / ideal_app_bw = ideal_runtime / sim_cycles
    workload_util_vals = []
    for actual_bw, ideal_app_bw in zip(actual_vals, ideal_app_vals):
        if math.isnan(actual_bw) or math.isnan(ideal_app_bw) or ideal_app_bw <= 0.0:
            workload_util_vals.append(float("nan"))
        else:
            workload_util_vals.append(actual_bw / ideal_app_bw * 100.0)
    actual_colors = [INTERCO_COLORS.get(e["interco_type"], "#333333") for e in entries]
    x = np.arange(len(entries), dtype=float)
    actual_width = 0.50

    fig, ax = plt.subplots(figsize=(max(9, 1.25 * len(entries)), 5.0))
    actual_bars = ax.bar(x, actual_vals, width=actual_width, color=actual_colors, label="Actual BW (completion)")
    _set_title(ax, "Bandwidth: actual vs ideal workload", subtitle)
    ax.set_ylabel("bit/cycle")
    ax.set_xlabel("Configuration", labelpad=50)
    _apply_interco_tick_labels(ax, x, entries)
    ax.set_axisbelow(True)
    ax.grid(axis="y", alpha=0.25)

    for bar, val, wl_util, bottleneck, interco_util in zip(
        actual_bars, actual_vals, workload_util_vals, ideal_bottleneck_vals, interco_util_vals
    ):
        if math.isnan(val):
            continue
        wl_util_txt = "n/a" if math.isnan(wl_util) else f"{wl_util:.1f}%"
        interco_util_txt = "n/a" if math.isnan(interco_util) else f"{interco_util:.1f}%"
        bottleneck_txt = "n/a" if math.isnan(bottleneck) else f"{bottleneck:.0f}"
        bar_cx = bar.get_x() + bar.get_width() / 2.0
        # Value on top of bar
        ax.text(bar_cx, val, f"{val:.1f} b/cyc", ha="center", va="bottom", fontsize=8)
        # Upper box: workload utilisation (transparent red, matching ideal-workload line)
        ax.text(
            bar_cx,
            val * 0.88,
            f"workload util: {wl_util_txt}",
            ha="center", va="center", fontsize=7, color=IDEAL_RED, zorder=8,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.75, edgecolor=IDEAL_RED, linewidth=0.8),
        )
        # Lower box: interco max BW + interco utilisation
        ax.text(
            bar_cx,
            val * 0.28,
            f"interco max: {bottleneck_txt} b/cyc\ninterco util: {interco_util_txt}",
            ha="center", va="center", fontsize=7, zorder=8,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="#cce5ff", alpha=0.85, edgecolor="none"),
        )

    # Ideal app BW computed from moved data and ideal application duration:
    # ideal_app_bw = effective_bw * total_real_sim_time / ideal_runtime
    valid_ideal_app_vals = [v for v in ideal_app_vals if not math.isnan(v)]
    if valid_ideal_app_vals:
        ideal_workload_bw = sum(valid_ideal_app_vals) / len(valid_ideal_app_vals)
        ax.axhline(y=ideal_workload_bw, color=IDEAL_RED, linestyle="--", linewidth=1.8, zorder=4)
        ax.text(
            0.98, ideal_workload_bw,
            f"ideal workload BW: {ideal_workload_bw:.1f} b/cyc",
            transform=ax.get_yaxis_transform(),
            ha="right", va="center",
            fontsize=7.5, color=IDEAL_RED, zorder=6,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.97, edgecolor=IDEAL_RED, linewidth=0.8),
        )

    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


# -----------------------------------------------------------------------
# Per-HW plots (fixed HW, sweep TB config)
# -----------------------------------------------------------------------

def _plot_total_sim_time_vs_tb(
    entries: List[Dict[str, object]],
    ideal_runtime: Optional[float],
    hw_label: str,
    out_path: Path,
    subtitle: str = "",
) -> None:
    entries = sorted(entries, key=_tb_sort_key)
    values = [e["total_sim_cycles"] for e in entries]
    colors = [TB_INVERT_COLORS.get(e.get("invert_prio"), TB_INVERT_COLORS[None]) for e in entries]
    x = np.arange(len(entries), dtype=float)

    fig, ax = plt.subplots(figsize=(max(8, 1.2 * len(entries)), 5.6))
    bars = ax.bar(x, values, color=colors, width=0.68)
    _set_title(ax, "Total simulation time vs testbench config", subtitle)
    ax.set_ylabel("cycles")
    ax.set_xlabel("Testbench config  (stall ratio / invert prio)", labelpad=40)
    _apply_tb_tick_labels(ax, x, entries)
    ax.set_axisbelow(True)
    ax.grid(axis="y", alpha=0.25)

    for bar, val in zip(bars, values):
        if math.isnan(val):
            continue
        bar_cx = bar.get_x() + bar.get_width() / 2.0
        ax.text(bar_cx, val, f"{val:.0f} cyc", ha="center", va="bottom", fontsize=8)
        if ideal_runtime is not None and ideal_runtime > 0:
            mult = val / ideal_runtime
            ax.annotate(
                f"{mult:.2f}× of ideal",
                xy=(bar_cx, val), xytext=(0, 16),
                textcoords="offset points",
                ha="center", va="bottom", fontsize=7, color=IDEAL_RED, zorder=8,
                bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.75, edgecolor=IDEAL_RED, linewidth=0.8),
            )

    legend = [
        Patch(facecolor=TB_INVERT_COLORS[0], label="invert prio off"),
        Patch(facecolor=TB_INVERT_COLORS[1], label="invert prio on"),
    ]
    if ideal_runtime is not None:
        ax.axhline(y=ideal_runtime, color=IDEAL_RED, linestyle="--", linewidth=1.6)
        ax.text(
            0.98, ideal_runtime,
            f"ideal workload runtime: {ideal_runtime:.0f} cyc",
            transform=ax.get_yaxis_transform(),
            ha="right", va="center",
            fontsize=7.5, color=IDEAL_RED, zorder=6,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.97, edgecolor=IDEAL_RED, linewidth=0.8),
        )
    ax.legend(handles=legend, loc="lower left")
    ax.margins(y=0.24)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def _plot_bandwidth_vs_tb(
    entries: List[Dict[str, object]],
    ideal_runtime: Optional[float],
    hw_label: str,
    out_path: Path,
    subtitle: str = "",
) -> None:
    entries = sorted(entries, key=_tb_sort_key)
    actual_vals = [e["actual_bw"] for e in entries]
    util_vals = [e["utilization_pct"] for e in entries]
    sim_cycles_vals = [e["total_sim_cycles"] for e in entries]
    colors = [TB_INVERT_COLORS.get(e.get("invert_prio"), TB_INVERT_COLORS[None]) for e in entries]

    ideal_app_vals = []
    for actual_bw, sim_cycles in zip(actual_vals, sim_cycles_vals):
        if ideal_runtime is None or math.isnan(actual_bw) or math.isnan(sim_cycles) or ideal_runtime <= 0.0:
            ideal_app_vals.append(float("nan"))
        else:
            ideal_app_vals.append(actual_bw * sim_cycles / ideal_runtime)

    # The HW bottleneck BW is the same for all entries; show as horizontal line.
    ideal_bottleneck = entries[0]["ideal_bottleneck_bw"] if entries else 0.0

    x = np.arange(len(entries), dtype=float)
    fig, ax = plt.subplots(figsize=(max(9, 1.25 * len(entries)), 5.0))
    bars = ax.bar(x, actual_vals, width=0.56, color=colors, label="Actual BW (completion)")
    _set_title(ax, "Bandwidth vs testbench config", subtitle)
    ax.set_ylabel("bit/cycle")
    ax.set_xlabel("Testbench config  (stall ratio / invert prio)", labelpad=40)
    _apply_tb_tick_labels(ax, x, entries)
    ax.set_axisbelow(True)
    ax.grid(axis="y", alpha=0.25)

    for bar, val, ideal_app_bw in zip(bars, actual_vals, ideal_app_vals):
        if math.isnan(val):
            continue
        bar_cx = bar.get_x() + bar.get_width() / 2.0
        # Value on top of bar
        ax.text(bar_cx, val, f"{val:.1f} b/cyc", ha="center", va="bottom", fontsize=8, zorder=8)
        # Workload util just inside bar top (red)
        wl_util_txt = "n/a" if math.isnan(ideal_app_bw) or ideal_app_bw <= 0 else f"{val / ideal_app_bw * 100:.1f}%"
        ax.text(
            bar_cx, val * 0.88,
            f"workload\nutil = {wl_util_txt}",
            ha="center", va="center", fontsize=7, color=IDEAL_RED, zorder=8,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.75, edgecolor=IDEAL_RED, linewidth=0.8),
        )

    legend = [
        Patch(facecolor=TB_INVERT_COLORS[0], label="invert prio off"),
        Patch(facecolor=TB_INVERT_COLORS[1], label="invert prio on"),
    ]

    valid_ideal_app_vals = [v for v in ideal_app_vals if not math.isnan(v)]
    if valid_ideal_app_vals:
        ideal_workload_bw = sum(valid_ideal_app_vals) / len(valid_ideal_app_vals)
        ax.axhline(y=ideal_workload_bw, color=IDEAL_RED, linestyle="--", linewidth=1.8, zorder=4)
        ax.text(
            0.98, ideal_workload_bw,
            f"ideal workload BW: {ideal_workload_bw:.1f} b/cyc",
            transform=ax.get_yaxis_transform(),
            ha="right", va="center",
            fontsize=7.5, color=IDEAL_RED, zorder=6,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", alpha=0.97, edgecolor=IDEAL_RED, linewidth=0.8),
        )

    ax.legend(handles=legend, loc="lower right")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def _plot_per_master_avg_req_to_gnt_vs_tb(
    entries: List[Dict[str, object]],
    hw_label: str,
    out_path: Path,
    subtitle: str = "",
) -> None:
    entries = sorted(entries, key=_tb_sort_key)
    _plot_per_master_avg_req_to_gnt(
        entries, out_path,
        tick_label_fn=_apply_tb_tick_labels,
        subtitle=subtitle,
    )


# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Plot sweep results from parsed transcript JSON files.")
    parser.add_argument(
        "--results-dir",
        default="target/verif/results",
        help="Directory containing parsed sweep JSON files (hardware_*.json).",
    )
    parser.add_argument(
        "--out-dir",
        default=None,
        help="Output directory for generated plots (default: <results-dir>/plots).",
    )
    parser.add_argument(
        "--ideal-run",
        default=None,
        help="Path to the ideal run JSON file for comparison.",
    )
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = Path(args.out_dir) if args.out_dir else results_dir / "plots"
    out_dir.mkdir(parents=True, exist_ok=True)
    ideal_json_path = Path(args.ideal_run) if args.ideal_run else None

    entries = _load_results(results_dir)
    if not entries:
        raise SystemExit(f"No sweep JSON files found in: {results_dir}")
    ideal_runtime = _parse_ideal_runtime(ideal_json_path)

    workload_label = results_dir.name
    if workload_label.startswith("workload_"):
        workload_label = workload_label[len("workload_"):]

    # -----------------------------------------------------------------
    # Group entries by full testbench config name for per-TB plots.
    # Each unique tb_name (e.g. testbench_invert_0_stall_4_5) gets its
    # own set of plots so different invert_prio values are never mixed.
    # Entries with no TB suffix are broadcast into every group so they
    # appear in all per-TB comparison plots.
    # -----------------------------------------------------------------
    log_entries: List = []
    tb_groups: Dict[str, List] = {}  # key: tb_name
    for e in entries:
        if e["tb_name"]:
            tb_groups.setdefault(e["tb_name"], []).append(e)
        else:
            log_entries.append(e)

    for tb_entries in tb_groups.values():
        tb_entries.extend(log_entries)

    # If there are only TB-less entries (no TB sweep at all), keep them as a
    # single group so the plots are still generated.
    if not tb_groups:
        tb_groups[""] = list(log_entries)

    # Per-TB plots: one set of 3 plots per full testbench config, using
    # the tb_name as the filename suffix.
    for tb_name, tb_entries in tb_groups.items():
        suffix = f"_{tb_name}" if tb_name else ""
        tb_entries.sort(key=lambda e: (
            e["n_hwpe"],
            e["hwpe_width_fact"],
            INTERCO_ORDER.get(e["interco_type"], 9),
        ))
        tb_subtitle = f"workload: {workload_label} | sweep: hw config"
        if tb_name:
            tb_subtitle += f" | tb: {tb_name}"
        _plot_total_sim_time(tb_entries, ideal_runtime, out_dir / f"total_simulation_time{suffix}.png", subtitle=tb_subtitle)
        _plot_per_master_avg_req_to_gnt(tb_entries, out_dir / f"avg_req_to_gnt_per_master{suffix}.png", subtitle=tb_subtitle)
        _plot_bandwidth(tb_entries, ideal_runtime, out_dir / f"bandwidth_ideal_vs_actual{suffix}.png", subtitle=tb_subtitle)

    # -----------------------------------------------------------------
    # Group entries by full HW config name
    # -----------------------------------------------------------------
    hw_groups: Dict[str, List] = {}
    for e in entries:
        hw_groups.setdefault(e["hw_name"], []).append(e)

    # Per-HW plots: sweep TB config on x-axis.
    # Only generated for HW configs that actually have multiple TB entries
    # (LOG configs have a single entry and produce no meaningful TB sweep).
    for hw_name, hw_entries in hw_groups.items():
        if len(hw_entries) <= 1:
            continue
        hw_label = hw_entries[0]["label"]  # short label for plot titles
        hw_subtitle = f"workload: {workload_label} | hw: {hw_label} | sweep: tb config"
        _plot_total_sim_time_vs_tb(hw_entries, ideal_runtime, hw_label, out_dir / f"total_simulation_time_vs_tb_{hw_name}.png", subtitle=hw_subtitle)
        _plot_bandwidth_vs_tb(hw_entries, ideal_runtime, hw_label, out_dir / f"bandwidth_vs_tb_{hw_name}.png", subtitle=hw_subtitle)
        _plot_per_master_avg_req_to_gnt_vs_tb(hw_entries, hw_label, out_dir / f"avg_req_to_gnt_per_master_vs_tb_{hw_name}.png", subtitle=hw_subtitle)

    print(f"Plots written to: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
