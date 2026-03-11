#!/usr/bin/env python3
"""Parse the final 'Simulation Summary' section from one transcript file."""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List


SUMMARY_MARKER = "------ Simulation Summary ------"


class ParseError(RuntimeError):
    """Raised when the transcript summary cannot be parsed."""


def _as_float(value: str) -> float:
    return float(value)


def _as_int(value: str) -> int:
    return int(value)


def _clean_line(raw: str) -> str:
    line = raw.strip()
    if line.startswith("#"):
        line = line[1:].strip()
    return line


def _summary_lines(transcript_text: str) -> List[str]:
    idx = transcript_text.rfind(SUMMARY_MARKER)
    if idx < 0:
        raise ParseError(f"Summary marker '{SUMMARY_MARKER}' not found.")
    return [_clean_line(line) for line in transcript_text[idx:].splitlines()]


def _ensure_master(masters: Dict[str, Dict[str, object]], master_name: str) -> Dict[str, object]:
    entry = masters.get(master_name)
    if entry is None:
        entry = {"master_name": master_name}
        masters[master_name] = entry
    return entry


def parse_summary(transcript_text: str) -> Dict[str, object]:
    lines = _summary_lines(transcript_text)

    result: Dict[str, object] = {
        "hw_config": {},
        "bandwidth": {},
        "simulation_time": {"per_master": []},
        "read_response_coverage": {},
        "transaction_counts": {},
        "request_to_grant_latency": {
            "per_master": [],
            "accumulated": {},
            "averages": {},
        },
        "finish": {},
    }

    masters: Dict[str, Dict[str, object]] = {}

    patterns = {
        "masters": re.compile(r"^Masters:\s*CORE=(\d+)\s*DMA=(\d+)\s*EXT=(\d+)\s*HWPE=(\d+)\s*\(total=(\d+)\)$"),
        "memory": re.compile(
            r"^Memory:\s*banks=(\d+)\s*total_size=(\d+)\s*kB\s*data_width=(\d+)\s*bits\s*hwpe_width=(\d+)\s*lanes$"
        ),
        "interconnect": re.compile(r"^Interconnect:\s*SEL_LIC=(\d+)\s*TS_BIT=(\d+)\s*EXPFIFO=(\d+)$"),
        "interconnect_side": re.compile(
            r"^Interconnect-side:\s*TYPE=(LOG|HCI|MUX|UNKNOWN)\s*N_NARROW_HCI=(\d+)\s*N_WIDE_HCI=(\d+)\s*N_DMA=(\d+)\s*N_EXT=(\d+)$"
        ),
        "id_addr": re.compile(r"^ID/address:\s*IW=(\d+)\s*ADDR_WIDTH=(\d+)\s*ADDR_WIDTH_BANK=(\d+)$"),
        "ideal_mem_bw": re.compile(r"^Ideal BW \(memory side\):\s*([0-9]+(?:\.[0-9]+)?)\s*bit/cycle"),
        "ideal_interco_bw": re.compile(r"^Ideal BW \(interco side\):\s*([0-9]+(?:\.[0-9]+)?)\s*bit/cycle"),
        "ideal_master_bw_legacy": re.compile(r"^Ideal BW \(master side\):\s*([0-9]+(?:\.[0-9]+)?)\s*bit/cycle"),
        "ideal_bottleneck_bw": re.compile(r"^Ideal BW \(bottleneck\):\s*([0-9]+(?:\.[0-9]+)?)\s*bit/cycle"),
        "actual_bw": re.compile(
            r"^Actual BW \(completion\):\s*([0-9]+(?:\.[0-9]+)?)\s*bit/cycle\s*\[utilization:\s*([0-9]+(?:\.[0-9]+)?)%\]$"
        ),
        "completion_bw_legacy": re.compile(r"^Completion bandwidth .*:\s*([0-9]+(?:\.[0-9]+)?)\s*bit/cycle$"),
        "completion_cycles": re.compile(r"^Completion phase duration:\s*([0-9]+(?:\.[0-9]+)?)\s*cycles$"),
        "granted": re.compile(r"^Granted transactions:\s*reads=(\d+)\s*writes=(\d+)\s*total=(\d+)$"),
        "read_complete": re.compile(r"^Read-complete responses:\s*(\d+)$"),
        "total_sim_cycles": re.compile(r"^Total simulation time:\s*([0-9]+(?:\.[0-9]+)?)\s*cycles$"),
        "per_master_sim_time": re.compile(r"^([A-Za-z0-9_]+)\s*\((master_[^)]+)\):\s*([0-9]+(?:\.[0-9]+)?)\s*cycles$"),
        "coverage": re.compile(r"^(master_[^:]+):\s*observed\s*(\d+)\s*/\s*expected\s*(\d+)$"),
        "tx_counts": re.compile(r"^(master_[^:]+):\s*granted reads=(\d+)\s*writes=(\d+),\s*read-complete=(\d+)$"),
        "req_gnt": re.compile(
            r"^(master_[^:]+):\s*avg req->gnt stall latency\s*([0-9]+(?:\.[0-9]+)?)\s*cycles over\s*(\d+)\s*grants$"
        ),
        "total_accum": re.compile(
            r"^Total accumulated req->gnt latency:\s*([0-9]+(?:\.[0-9]+)?)\s*cycles over\s*(\d+)\s*grants$"
        ),
        "class_avg": re.compile(
            r"^(LOG|HWPE|Global) avg req->gnt stall latency "
            r"\((weighted by grant count|mean of per-master averages)\):\s*([0-9]+(?:\.[0-9]+)?)\s*cycles$"
        ),
        "finish_note": re.compile(r"^\*\* Note: \$finish\s*:\s*(.+)\((\d+)\)$"),
        "finish_time": re.compile(r"^Time:\s*([0-9]+)\s*ps\s*Iteration:\s*(\d+)\s*Instance:\s*(.+)$"),
    }

    for line in lines:
        if not line or line == SUMMARY_MARKER:
            continue

        match = patterns["masters"].match(line)
        if match:
            result["hw_config"]["masters"] = {
                "core": _as_int(match.group(1)),
                "dma": _as_int(match.group(2)),
                "ext": _as_int(match.group(3)),
                "hwpe": _as_int(match.group(4)),
                "total": _as_int(match.group(5)),
            }
            continue

        match = patterns["memory"].match(line)
        if match:
            result["hw_config"]["memory"] = {
                "banks": _as_int(match.group(1)),
                "total_size_kb": _as_int(match.group(2)),
                "data_width_bits": _as_int(match.group(3)),
                "hwpe_width_lanes": _as_int(match.group(4)),
            }
            continue

        match = patterns["interconnect"].match(line)
        if match:
            result["hw_config"]["interconnect"] = {
                "sel_lic": _as_int(match.group(1)),
                "ts_bit": _as_int(match.group(2)),
                "expfifo": _as_int(match.group(3)),
            }
            continue

        match = patterns["interconnect_side"].match(line)
        if match:
            narrow_hci = _as_int(match.group(2))
            wide_hci = _as_int(match.group(3))
            n_dma = _as_int(match.group(4))
            n_ext = _as_int(match.group(5))
            result["hw_config"]["interconnect_side"] = {
                "type": match.group(1),
                "n_narrow_hci": narrow_hci,
                "n_wide_hci": wide_hci,
                "n_dma": n_dma,
                "n_ext": n_ext,
                "narrow_total_ports": narrow_hci + n_dma + n_ext,
                "total_initiator_ports": narrow_hci + wide_hci + n_dma + n_ext,
            }
            continue

        match = patterns["id_addr"].match(line)
        if match:
            result["hw_config"]["id_address"] = {
                "iw": _as_int(match.group(1)),
                "addr_width": _as_int(match.group(2)),
                "addr_width_bank": _as_int(match.group(3)),
            }
            continue

        match = patterns["ideal_mem_bw"].match(line)
        if match:
            result["bandwidth"]["ideal_memory_side_bit_per_cycle"] = _as_float(match.group(1))
            continue

        match = patterns["ideal_interco_bw"].match(line)
        if match:
            result["bandwidth"]["ideal_interconnect_side_bit_per_cycle"] = _as_float(match.group(1))
            continue

        match = patterns["ideal_master_bw_legacy"].match(line)
        if match:
            result["bandwidth"]["ideal_interconnect_side_bit_per_cycle"] = _as_float(match.group(1))
            continue

        match = patterns["ideal_bottleneck_bw"].match(line)
        if match:
            result["bandwidth"]["ideal_bottleneck_bit_per_cycle"] = _as_float(match.group(1))
            continue

        match = patterns["actual_bw"].match(line)
        if match:
            result["bandwidth"]["actual_completion_bit_per_cycle"] = _as_float(match.group(1))
            result["bandwidth"]["actual_completion_utilization_pct"] = _as_float(match.group(2))
            continue

        match = patterns["completion_bw_legacy"].match(line)
        if match:
            result["bandwidth"]["actual_completion_bit_per_cycle"] = _as_float(match.group(1))
            continue

        match = patterns["completion_cycles"].match(line)
        if match:
            result["bandwidth"]["completion_phase_duration_cycles"] = _as_float(match.group(1))
            continue

        match = patterns["granted"].match(line)
        if match:
            result["bandwidth"]["granted_transactions"] = {
                "reads": _as_int(match.group(1)),
                "writes": _as_int(match.group(2)),
                "total": _as_int(match.group(3)),
            }
            continue

        match = patterns["read_complete"].match(line)
        if match:
            result["bandwidth"]["read_complete_responses"] = _as_int(match.group(1))
            continue

        match = patterns["total_sim_cycles"].match(line)
        if match:
            result["simulation_time"]["total_cycles"] = _as_float(match.group(1))
            continue

        match = patterns["per_master_sim_time"].match(line)
        if match:
            role_name = match.group(1)
            master_name = match.group(2)
            sim_cycles = _as_float(match.group(3))
            entry = _ensure_master(masters, master_name)
            entry["role_name"] = role_name
            entry["sim_time_cycles"] = sim_cycles
            continue

        match = patterns["coverage"].match(line)
        if match:
            master_name = match.group(1)
            observed = _as_int(match.group(2))
            expected = _as_int(match.group(3))
            entry = _ensure_master(masters, master_name)
            entry["read_observed"] = observed
            entry["read_expected"] = expected
            result["read_response_coverage"][master_name] = {
                "observed": observed,
                "expected": expected,
            }
            continue

        match = patterns["tx_counts"].match(line)
        if match:
            master_name = match.group(1)
            reads = _as_int(match.group(2))
            writes = _as_int(match.group(3))
            read_complete = _as_int(match.group(4))
            entry = _ensure_master(masters, master_name)
            entry["granted_reads"] = reads
            entry["granted_writes"] = writes
            entry["read_complete"] = read_complete
            result["transaction_counts"][master_name] = {
                "granted_reads": reads,
                "granted_writes": writes,
                "read_complete": read_complete,
            }
            continue

        match = patterns["req_gnt"].match(line)
        if match:
            master_name = match.group(1)
            avg_cycles = _as_float(match.group(2))
            grants = _as_int(match.group(3))
            entry = _ensure_master(masters, master_name)
            entry["avg_req_to_gnt_stall_latency_cycles"] = avg_cycles
            entry["req_to_gnt_grants"] = grants
            continue

        match = patterns["total_accum"].match(line)
        if match:
            result["request_to_grant_latency"]["accumulated"] = {
                "cycles": _as_float(match.group(1)),
                "grants": _as_int(match.group(2)),
            }
            continue

        match = patterns["class_avg"].match(line)
        if match:
            group = match.group(1).lower()
            avg_type = match.group(2)
            value = _as_float(match.group(3))
            key = "weighted_cycles" if "weighted by grant count" in avg_type else "unweighted_cycles"
            averages = result["request_to_grant_latency"]["averages"]
            group_entry = averages.get(group, {})
            group_entry[key] = value
            averages[group] = group_entry
            continue

        match = patterns["finish_note"].match(line)
        if match:
            result["finish"]["source"] = match.group(1).strip()
            result["finish"]["line"] = _as_int(match.group(2))
            continue

        match = patterns["finish_time"].match(line)
        if match:
            result["finish"]["time_ps"] = _as_int(match.group(1))
            result["finish"]["iteration"] = _as_int(match.group(2))
            result["finish"]["instance"] = match.group(3).strip()
            continue

    sorted_masters = [masters[name] for name in sorted(masters.keys())]
    result["simulation_time"]["per_master"] = [
        {
            "master_name": row["master_name"],
            "role_name": row.get("role_name"),
            "sim_time_cycles": row.get("sim_time_cycles"),
        }
        for row in sorted_masters
    ]
    result["request_to_grant_latency"]["per_master"] = [
        {
            "master_name": row["master_name"],
            "avg_req_to_gnt_stall_latency_cycles": row.get("avg_req_to_gnt_stall_latency_cycles"),
            "req_to_gnt_grants": row.get("req_to_gnt_grants"),
        }
        for row in sorted_masters
    ]
    result["masters"] = sorted_masters

    return result


def _cli_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Parse final Simulation Summary lines from one transcript.")
    parser.add_argument("--transcript", required=True, help="Path to transcript file")
    parser.add_argument("--out", default="", help="Optional output JSON file path")
    return parser.parse_args()


def main() -> int:
    args = _cli_args()
    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        raise ParseError(f"Transcript not found: {transcript_path}")

    text = transcript_path.read_text(encoding="utf-8", errors="replace")
    parsed = parse_summary(text)

    output = json.dumps(parsed, indent=2, sort_keys=False)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output + "\n", encoding="ascii")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ParseError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
