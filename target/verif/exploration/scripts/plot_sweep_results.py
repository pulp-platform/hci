#!/usr/bin/env python3
"""Plot sweep metrics from parsed transcript JSON files."""

import argparse
import json
import math
import re
from pathlib import Path
from typing import Dict, List, Tuple

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


def _parse_cfg_from_filename(path: Path) -> Tuple[str, int, int]:
    match = re.match(r"^hardware_([a-zA-Z]+)_([0-9]+)hwpe_([0-9]+)fact\.json$", path.name)
    if not match:
        return ("UNK", 0, 0)
    return (match.group(1).upper(), int(match.group(2)), int(match.group(3)))


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

        interco_from_name, n_hwpe_name, wf_name = _parse_cfg_from_filename(path)
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

        entries.append(
            {
                "path": path,
                "label": cfg_label,
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

def _apply_interco_tick_labels(ax, x_positions, entries) -> None:
    """Replace x-tick labels with three-line labels: INTERCO_TYPE / N cores / M HWPEs."""
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


def _plot_total_sim_time(entries: List[Dict[str, object]], ideal_runtime: float, out_path: Path) -> None:
    values = [e["total_sim_cycles"] for e in entries]
    colors = [INTERCO_COLORS.get(e["interco_type"], "#333333") for e in entries]
    x = np.arange(len(entries), dtype=float)

    fig, ax = plt.subplots(figsize=(max(8, 1.2 * len(entries)), 5.6))
    bars = ax.bar(x, values, color=colors, width=0.68)
    ax.set_title("Total simulation time vs ideal workload runtime")
    ax.set_ylabel("cycles")
    ax.set_xlabel("Configuration", labelpad=50)
    _apply_interco_tick_labels(ax, x, entries)
    ax.set_axisbelow(True)
    ax.grid(axis="y", alpha=0.25)

    for bar, val in zip(bars, values):
        if math.isnan(val):
            continue
        if ideal_runtime is not None:
            mult_of_ideal = (val / ideal_runtime) if val > 0 and ideal_runtime > 0 else float("nan")
            pct_txt = "n/a" if math.isnan(mult_of_ideal) else f"{mult_of_ideal:.2f}X of ideal runtime"
            label_txt = f"{val:.0f}\n({pct_txt})"
        else:
            label_txt = f"{val:.0f}"
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            val,
            label_txt,
            ha="center",
            va="bottom",
            fontsize=8,
        )

    legend = [Patch(facecolor=INTERCO_COLORS[k], label=k) for k in ("LOG", "HCI", "MUX")]
    if ideal_runtime is not None:
        ax.axhline(
            y=ideal_runtime,
            color="red",
            linestyle="--",
            linewidth=1.6,
            label=f"Ideal workload runtime ({ideal_runtime:.0f} cycles)",
        )
        legend.append(Line2D([0], [0], color="red", linestyle="--", linewidth=1.6, label="Ideal workload runtime"))
    ax.legend(handles=legend, loc="lower left")
    ax.margins(y=0.24)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def _plot_per_master_avg_req_to_gnt(entries: List[Dict[str, object]], out_path: Path) -> None:
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
    ax.set_title("Avg req->gnt stall latency per master")
    ax.set_xlabel("Configuration", labelpad=50)
    ax.set_ylabel("Master")
    _apply_interco_tick_labels(ax, np.arange(len(entries), dtype=float), entries)
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


def _plot_bandwidth(entries: List[Dict[str, object]], ideal_runtime: float, out_path: Path) -> None:
    ideal_vals = [e["ideal_bottleneck_bw"] for e in entries]
    actual_vals = [e["actual_bw"] for e in entries]
    util_vals = [e["utilization_pct"] for e in entries]
    sim_cycles_vals = [e["total_sim_cycles"] for e in entries]
    ideal_app_vals = []
    for actual_bw, sim_cycles in zip(actual_vals, sim_cycles_vals):
        if ideal_runtime is None or math.isnan(actual_bw) or math.isnan(sim_cycles) or ideal_runtime <= 0.0:
            ideal_app_vals.append(float("nan"))
        else:
            ideal_app_vals.append(actual_bw * sim_cycles / ideal_runtime)
    actual_colors = [INTERCO_COLORS.get(e["interco_type"], "#333333") for e in entries]
    x = np.arange(len(entries), dtype=float)
    ideal_width = 0.20
    actual_width = 0.34

    fig, ax = plt.subplots(figsize=(max(9, 1.25 * len(entries)), 5.0))
    ideal_bars = ax.bar(
        x - actual_width / 2.0,
        ideal_vals,
        width=ideal_width,
        color=IDEAL_COLOR,
        label="Max interco bandwidth",
    )
    actual_bars = ax.bar(x + ideal_width / 2.0, actual_vals, width=actual_width, color=actual_colors, label="Actual BW (completion)")
    ax.set_title("Bandwidth: interconnect-side ideal vs actual")
    ax.set_ylabel("bit/cycle")
    ax.set_xlabel("Configuration", labelpad=50)
    _apply_interco_tick_labels(ax, x, entries)
    ax.set_axisbelow(True)
    ax.grid(axis="y", alpha=0.25)

    for bar, val in zip(ideal_bars, ideal_vals):
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            val,
            f"{val:.0f}",
            ha="center",
            va="bottom",
            fontsize=8,
            zorder=8,
        )
    for bar, val, util in zip(actual_bars, actual_vals, util_vals):
        if math.isnan(val):
            continue
        util_txt = "n/a" if math.isnan(util) else f"{util:.1f}% interco util"
        ax.text(
            bar.get_x() + bar.get_width() / 2.0,
            val,
            f"{val:.1f}\n({util_txt})",
            ha="center",
            va="bottom",
            fontsize=8,
            zorder=8,
        )

    # Ideal app BW computed from moved data and ideal application duration:
    # ideal_app_bw = effective_bw * total_real_sim_time / ideal_runtime
    valid_ideal_app_vals = [v for v in ideal_app_vals if not math.isnan(v)]
    if valid_ideal_app_vals:
        ideal_workload_bw = sum(valid_ideal_app_vals) / len(valid_ideal_app_vals)
        ax.axhline(
            y=ideal_workload_bw,
            color="red",
            linestyle="--",
            linewidth=1.8,
            label="Ideal workload bandwidth",
            zorder=4,
        )
        ax.text(
            x[-1] + 0.35,
            ideal_workload_bw,
            f"{ideal_workload_bw:.1f}",
            color="red",
            fontsize=9,
            ha="right",
            va="bottom",
            zorder=8,
        )

    interco_legend = [Patch(facecolor=INTERCO_COLORS[k], label=f"Actual {k}") for k in ("LOG", "HCI", "MUX")]
    base_legend = [Patch(facecolor=IDEAL_COLOR, label="Max interco bandwidth")]
    extra_legend = [Line2D([0], [0], color="red", linestyle="--", linewidth=1.8, label="Ideal workload bandwidth")]
    ax.legend(handles=base_legend + interco_legend + extra_legend, loc="best")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description="Plot sweep results from parsed transcript JSON files.")
    parser.add_argument(
        "--results-dir",
        default="target/verif/results",
        help="Directory containing parsed sweep JSON files (hardware_*.json).",
    )
    parser.add_argument(
        "--out-dir",
        default="target/verif/results/plots",
        help="Output directory for generated plots.",
    )
    parser.add_argument(
        "--ideal-run",
        default=None,
        help="Path to the ideal run JSON file for comparison.",
    )
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ideal_json_path = Path(args.ideal_run) if args.ideal_run else None

    # Parse results
    entries = _load_results(results_dir)
    if not entries:
        raise SystemExit(f"No sweep JSON files found in: {results_dir}")
    ideal_runtime = _parse_ideal_runtime(ideal_json_path)

    # Plot
    _plot_total_sim_time(entries, ideal_runtime, out_dir / "total_simulation_time.png")
    _plot_per_master_avg_req_to_gnt(entries, out_dir / "avg_req_to_gnt_per_master.png")
    _plot_bandwidth(entries, ideal_runtime, out_dir / "bandwidth_ideal_vs_actual.png")

    print(f"Plots written to: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
