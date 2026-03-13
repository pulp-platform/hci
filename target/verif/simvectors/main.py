"""Stimuli generator (reads JSON configs in `verif/config`).

This script is invoked by the top-level Makefile and expects three
JSON config files: workload, testbench and hardware. It produces
cycle-accurate stimuli in `verif/simvectors/generated/stimuli`.

Each stimuli file encodes an offered per-cycle request stream plus PAUSE fence tokens.

Idle lines (req=0) represent intended issue gaps in the absence of backpressure.
The application driver may consume some idle entries while stalled on an earlier
request grant, and hide some memory/interconnect latency. So the file is not a
strict wall-clock replay under contention.

Stimuli line format:
  req(1b) id(IWb) wen(1b) data(Nb) add(Ab)
"""

import json
import math
import sys
from pathlib import Path
import argparse

code_directory = Path(__file__).resolve().parent

try:
    from hci_stimuli import StimuliGenerator
    from memory_report import write_memory_map_txt
    from html_report import write_memory_lifetime_html
except Exception:
    sys.path.insert(0, str(code_directory))
    from hci_stimuli import StimuliGenerator
    from memory_report import write_memory_map_txt
    from html_report import write_memory_lifetime_html


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Generate stimuli from JSON configs.")
    parser.add_argument('--workload_config', required=True, help="Path to JSON workload configuration file")
    parser.add_argument('--testbench_config', required=True, help="Path to JSON testbench configuration file")
    parser.add_argument('--hardware_config', required=True, help="Path to JSON hardware configuration file")
    parser.add_argument('--emit_phases_mk', default=None, metavar='PATH',
                        help="Also write the phases.mk Makefile fragment to PATH")
    parser.add_argument(
        '--golden',
        action='store_true',
        help=(
            "Also emit golden read-data vectors under verif/simvectors/generated/golden. "
            "This assumes a per-master sequential memory model (initial = all 1s, updated by that master's writes)."
        ),
    )
    return parser.parse_args(argv)


def load_config(filename, description):
    try:
        with open(filename, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"ERROR: {description} file not found: {filename}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in {description} file: {e}")
        sys.exit(1)


### MAIN ENTRYPOINT ###
def main(argv=None):
    args = parse_args(argv)

    hardware_config = load_config(args.hardware_config, "Hardware configuration")
    testbench_config = load_config(args.testbench_config, "Testbench configuration")
    workload_config = load_config(args.workload_config, "Workload configuration")

    # Hardware parameters
    hw_params = hardware_config['parameters']
    N_BANKS = hw_params['N_BANKS']
    TOT_MEM_SIZE = hw_params['TOT_MEM_SIZE']
    DATA_WIDTH = hw_params['DATA_WIDTH']
    N_CORE = hw_params['N_CORE']
    N_DMA = hw_params['N_DMA']
    N_EXT = hw_params['N_EXT']
    N_HWPE = hw_params['N_HWPE']
    HWPE_WIDTH_FACT = hw_params['HWPE_WIDTH_FACT']
    N_CORE_CFG = N_CORE
    N_DMA_CFG = N_DMA
    N_EXT_CFG = N_EXT
    N_HWPE_CFG = N_HWPE

    log_masters = workload_config['log_masters']
    hwpe_masters = workload_config['hwpe_masters']

    # Derived parameters
    ADD_WIDTH = math.ceil(math.log2(TOT_MEM_SIZE * 1024))
    N_LOG = N_CORE + N_DMA + N_EXT
    N_LOG_CFG = N_LOG
    IW = 8

    def _narrow_driver_name(local_idx: int) -> str:
        idx = int(local_idx)
        if idx < N_CORE_CFG:
            return f"core_{idx}"
        idx -= N_CORE_CFG
        if idx < N_DMA_CFG:
            return f"dma_{idx}"
        idx -= N_DMA_CFG
        if idx < N_EXT_CFG:
            return f"ext_{idx}"
        return f"narrow_{local_idx}"

    # Validations
    if len(log_masters) != N_LOG:
        print(f"ERROR: Number of log masters in workload config ({len(log_masters)}) doesn't match hardware config N_LOG ({N_LOG})")
        sys.exit(1)
    if len(hwpe_masters) != N_HWPE:
        print(f"ERROR: Number of HWPE masters in workload config ({len(hwpe_masters)}) doesn't match hardware config N_HWPE ({N_HWPE})")
        sys.exit(1)
    if N_LOG + N_HWPE < 1:
        print("ERROR: the number of masters must be > 0")
        sys.exit(1)
    n_words = (TOT_MEM_SIZE * 1024 / N_BANKS) / (DATA_WIDTH / 8)
    if not n_words.is_integer():
        print("ERROR: the number of words is not an integer value")
        sys.exit(1)

    # Prepare output dirs
    simvectors_dir = code_directory.resolve()
    generated_dir = (simvectors_dir / 'generated').resolve()
    stimuli_dir = (generated_dir / 'stimuli').resolve()
    generated_dir.mkdir(parents=True, exist_ok=True)
    stimuli_dir.mkdir(parents=True, exist_ok=True)

    def _create_idle_file(path: Path, data_width: int):
        """Write a single idle line for a master that is not present in hardware."""
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "0 " + "0" * IW + " 0 " + "0" * data_width + " " + "0" * ADD_WIDTH + "\n",
            encoding='ascii',
        )

    CORE_ZERO_FLAG = False
    DMA_ZERO_FLAG = False
    EXT_ZERO_FLAG = False
    HWPE_ZERO_FLAG = False

    if N_CORE <= 0:
        CORE_ZERO_FLAG = True
        N_CORE = 1
        _create_idle_file(stimuli_dir / 'master_log_0.txt', DATA_WIDTH)
    if N_DMA <= 0:
        DMA_ZERO_FLAG = True
        N_DMA = 1
        _create_idle_file(stimuli_dir / f'master_log_{N_CORE}.txt', DATA_WIDTH)
    if N_EXT <= 0:
        EXT_ZERO_FLAG = True
        N_EXT = 1
        _create_idle_file(stimuli_dir / f'master_log_{N_CORE + N_DMA}.txt', DATA_WIDTH)
    if N_HWPE <= 0:
        HWPE_ZERO_FLAG = True
        N_HWPE = 1
        _create_idle_file(stimuli_dir / 'master_hwpe_0.txt', HWPE_WIDTH_FACT * DATA_WIDTH)

    next_start_id = 0

    # Memory map entries collected during generation, printed at the end
    memory_map_entries = []

    def _bank_of(byte_addr):
        return (byte_addr // (DATA_WIDTH // 8)) % N_BANKS

    def _record_memory_map(kind, local_idx, description, config, n_test, data_width, access_bytes,
                           region_base, region_size, start_address, stride0, len_d0,
                           stride1, len_d1, stride2, master_config, total_mem_bytes):
        if kind == 'master_log':
            label_prefix = _narrow_driver_name(local_idx)
        elif kind == 'master_hwpe':
            label_prefix = f"hwpe_{local_idx}"
        else:
            label_prefix = f"{kind}_{local_idx}"
        label = label_prefix + (f" ({description})" if description else "")
        if config == 'idle' or n_test == 0:
            memory_map_entries.append({'label': label, 'pattern': config, 'n': 0,
                                       'info': 'idle - no memory accesses'})
            return

        first_addr = last_addr = None
        detail = {}

        if config == 'random':
            first_addr = region_base
            last_addr = region_base + region_size - access_bytes
            detail['region'] = f"0x{region_base:08x} - 0x{region_base + region_size - 1:08x}  ({region_size} B)"
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                rpct = master_config.get('traffic_read_pct', 50)
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
                detail['read_pct']    = f"{rpct}%"
        elif config == 'matmul_phased':
            ra = _parse_maybe_bin_int(master_config.get('region_base_address_a'), None)
            sa = _parse_maybe_bin_int(master_config.get('region_size_bytes_a'),   None)
            rb = _parse_maybe_bin_int(master_config.get('region_base_address_b'), None)
            sb = _parse_maybe_bin_int(master_config.get('region_size_bytes_b'),   None)
            rc = _parse_maybe_bin_int(master_config.get('region_base_address_c'), None)
            sc = _parse_maybe_bin_int(master_config.get('region_size_bytes_c'),   None)
            if ra is not None and sa is not None:
                # Explicit per-phase regions
                a_base, a_size = ra, sa
                b_base, b_size = (rb, sb) if rb is not None and sb is not None else (ra, sa)
                c_base, c_size = (rc, sc) if rc is not None and sc is not None else (ra, sa)
                detail['matrix_A (read)']  = f"0x{a_base:08x} - 0x{a_base + a_size - access_bytes:08x}  ({a_size} B)"
                if int(master_config.get('matmul_ratio_b', 1)) > 0:
                    detail['matrix_B (read)']  = f"0x{b_base:08x} - 0x{b_base + b_size - access_bytes:08x}  ({b_size} B)"
                detail['matrix_C (write)'] = f"0x{c_base:08x} - 0x{c_base + c_size - access_bytes:08x}  ({c_size} B)"
                first_addr = a_base
                last_addr  = c_base + c_size - access_bytes
            else:
                # Auto-split combined region into thirds
                a_words = max(1, (region_size // access_bytes) // 3)
                b_words = max(1, (region_size // access_bytes) // 3)
                c_words = (region_size // access_bytes) - a_words - b_words
                a_base = region_base
                b_base = a_base + a_words * access_bytes
                c_base = b_base + b_words * access_bytes
                detail['region'] = f"0x{region_base:08x} - 0x{region_base + region_size - 1:08x}  ({region_size} B)  [auto-split]"
                detail['matrix_A (read)']  = f"0x{a_base:08x} - 0x{b_base - access_bytes:08x}  ({a_words * access_bytes} B)"
                detail['matrix_B (read)']  = f"0x{b_base:08x} - 0x{c_base - access_bytes:08x}  ({b_words * access_bytes} B)"
                detail['matrix_C (write)'] = f"0x{c_base:08x} - 0x{c_base + c_words * access_bytes - access_bytes:08x}  ({c_words * access_bytes} B)"
                first_addr = a_base
                last_addr  = c_base + c_words * access_bytes - access_bytes
            if all(k in master_config for k in ('matrix_m', 'matrix_n', 'matrix_k')):
                m, n, k = int(master_config['matrix_m']), int(master_config['matrix_n']), int(master_config['matrix_k'])
                detail['matrix_dims'] = f"M={m} N={n} K={k}  (A: {m}x{k}, B: {k}x{n}, C: {m}x{n})"
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
            idle_between = master_config.get('idle_cycles_between_phases', 0)
            if idle_between:
                detail['idle_between_phases'] = f"{idle_between} cycles"
        elif config == 'multi_linear':
            regs = master_config.get('regions', []) or []
            detail['schedule'] = str(master_config.get('schedule', 'round_robin'))
            detail['burst_len'] = int(master_config.get('burst_len', 1))
            for idx, reg in enumerate(regs):
                base = _parse_maybe_bin_int(reg.get('base'), 0)
                size = _parse_maybe_bin_int(reg.get('size_bytes'), 0)
                stride_w = int(reg.get('stride_words', 1))
                rpct = reg.get('read_pct')
                rpct_txt = f", read={int(rpct)}%" if rpct is not None else ""
                detail[f"region_{idx}"] = (
                    f"0x{base:08x} - 0x{base + max(0, size) - 1:08x}  "
                    f"({size} B, stride={stride_w} words{rpct_txt})"
                )
            if regs:
                first_addr = _parse_maybe_bin_int(regs[0].get('base'), 0)
                last_reg = regs[-1]
                lb = _parse_maybe_bin_int(last_reg.get('base'), 0)
                ls = _parse_maybe_bin_int(last_reg.get('size_bytes'), 0)
                last_addr = lb + max(0, ls) - access_bytes
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
        elif config == 'bank_group_linear':
            span = max(1, int(master_config.get('bank_group_span', 1)))
            start_bank = int(master_config.get('start_bank', 0)) % max(1, int(N_BANKS))
            stride_beats = max(1, int(master_config.get('stride_beats', 1)))
            first_addr = start_bank * access_bytes
            phase = max(0, n_test - 1) * stride_beats
            group_idx = phase // span
            bank = (start_bank + (phase % span)) % max(1, int(N_BANKS))
            last_addr = (group_idx * N_BANKS + bank) * access_bytes
            last_addr = last_addr % total_mem_bytes
            detail['start_bank'] = start_bank
            detail['bank_group_span'] = span
            detail['stride_beats'] = stride_beats
            if 'bank_group_hop' in master_config:
                detail['bank_group_hop'] = int(master_config.get('bank_group_hop', 0))
            if 'wen' in master_config:
                detail['wen'] = int(master_config.get('wen', 1))
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
        elif config == 'rw_rowwise':
            row_base = _parse_maybe_bin_int(master_config.get('row_base_address'), region_base)
            row_size = _parse_maybe_bin_int(master_config.get('row_size_bytes'), access_bytes)
            n_rows = max(0, int(master_config.get('n_rows', 0)))
            row_stride = _parse_maybe_bin_int(master_config.get('row_stride_bytes'), row_size)
            rpr = max(0, int(master_config.get('reads_per_row', 0)))
            wpr = max(0, int(master_config.get('writes_per_row', 0)))
            first_addr = row_base
            last_addr = row_base + max(0, n_rows - 1) * row_stride + max(0, row_size - access_bytes)
            last_addr = last_addr % total_mem_bytes
            detail['rows'] = f"n_rows={n_rows}, row_size={row_size} B, row_stride={row_stride} B"
            detail['per_row'] = f"reads={rpr}, writes={wpr}"
            idle_between = int(master_config.get('idle_cycles_between_rows', 0))
            if idle_between:
                detail['idle_between_rows'] = f"{idle_between} cycles"
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
        elif config == 'gather_scatter':
            rr = master_config.get('read_regions', []) or []
            wr = master_config.get('write_region', {}) or {}
            for idx, reg in enumerate(rr):
                b = _parse_maybe_bin_int(reg.get('base'), 0)
                s = _parse_maybe_bin_int(reg.get('size_bytes'), 0)
                detail[f"read_region_{idx}"] = f"0x{b:08x} - 0x{b + max(0, s) - 1:08x}  ({s} B)"
            wb = _parse_maybe_bin_int(wr.get('base'), 0)
            ws = _parse_maybe_bin_int(wr.get('size_bytes'), 0)
            detail['write_region'] = f"0x{wb:08x} - 0x{wb + max(0, ws) - 1:08x}  ({ws} B)"
            detail['schedule'] = str(master_config.get('schedule', '4read_1write'))
            detail['chunk_bytes'] = int(_parse_maybe_bin_int(master_config.get('chunk_bytes'), access_bytes))
            if rr:
                first_addr = _parse_maybe_bin_int(rr[0].get('base'), 0)
            else:
                first_addr = wb
            last_addr = wb + max(0, ws) - access_bytes if ws > 0 else first_addr
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
        elif config == 'matmul_tiled_interleave':
            ra = _parse_maybe_bin_int(master_config.get('region_base_address_a'), region_base)
            sa = _parse_maybe_bin_int(master_config.get('region_size_bytes_a'), region_size // 3)
            rb = _parse_maybe_bin_int(master_config.get('region_base_address_b'), ra + sa)
            sb = _parse_maybe_bin_int(master_config.get('region_size_bytes_b'), region_size // 3)
            rc = _parse_maybe_bin_int(master_config.get('region_base_address_c'), rb + sb)
            sc = _parse_maybe_bin_int(master_config.get('region_size_bytes_c'), region_size - max(0, sa) - max(0, sb))
            detail['matrix_A (read)'] = f"0x{ra:08x} - 0x{ra + max(0, sa) - access_bytes:08x}  ({sa} B)"
            detail['matrix_B (read)'] = f"0x{rb:08x} - 0x{rb + max(0, sb) - access_bytes:08x}  ({sb} B)"
            detail['matrix_C (write)'] = f"0x{rc:08x} - 0x{rc + max(0, sc) - access_bytes:08x}  ({sc} B)"
            detail['tile_bytes'] = (
                f"A={int(_parse_maybe_bin_int(master_config.get('tile_a_bytes'), access_bytes))}, "
                f"B={int(_parse_maybe_bin_int(master_config.get('tile_b_bytes'), access_bytes))}, "
                f"C={int(_parse_maybe_bin_int(master_config.get('tile_c_bytes'), access_bytes))}"
            )
            detail['tiles'] = int(master_config.get('tiles', 1))
            detail['ab_c_schedule'] = str(master_config.get('ab_c_schedule', 'A_B_C'))
            idle_tiles = int(master_config.get('idle_cycles_between_tiles', 0))
            if idle_tiles:
                detail['idle_between_tiles'] = f"{idle_tiles} cycles"
            first_addr = ra
            last_addr = rc + max(0, sc) - access_bytes
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
        elif config == 'hotspot_random':
            hrs = master_config.get('hot_regions', []) or []
            for idx, reg in enumerate(hrs):
                b = _parse_maybe_bin_int(reg.get('base'), 0)
                s = _parse_maybe_bin_int(reg.get('size_bytes'), 0)
                w = int(reg.get('weight', 1))
                detail[f"hot_region_{idx}"] = f"0x{b:08x} - 0x{b + max(0, s) - 1:08x}  ({s} B, weight={w})"
            if hrs:
                first_addr = _parse_maybe_bin_int(hrs[0].get('base'), 0)
                lb = _parse_maybe_bin_int(hrs[-1].get('base'), 0)
                ls = _parse_maybe_bin_int(hrs[-1].get('size_bytes'), 0)
                last_addr = lb + max(0, ls) - access_bytes
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                rpct = master_config.get('traffic_read_pct', 50)
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
                detail['read_pct'] = f"{rpct}%"
        elif config == 'linear':
            base = int(start_address, 2) if set(start_address) <= {'0','1'} else int(start_address, 0)
            first_addr = base
            last_addr = base + (n_test - 1) * stride0 * access_bytes
            last_addr = last_addr % total_mem_bytes
            detail['start'] = f"0x{base:08x}"
            detail['stride'] = f"{stride0} words ({stride0 * access_bytes} B)"
            tpct = master_config.get('traffic_pct')
            if tpct is not None:
                rpct = master_config.get('traffic_read_pct', 50)
                n_idles_per_req = max(0, round((100 - int(tpct)) / int(tpct))) if int(tpct) < 100 else 0
                detail['traffic_pct'] = f"{tpct}%  ({n_idles_per_req} idle(s) after each transaction)"
                detail['read_pct']    = f"{rpct}%"
        elif config == '2d':
            base = int(start_address, 2) if set(start_address) <= {'0','1'} else int(start_address, 0)
            first_addr = base
            last_addr = (base + (len_d0 - 1) * stride0 * access_bytes
                         + (n_test // max(len_d0, 1) - 1) * stride1 * access_bytes) % total_mem_bytes
            detail['dims'] = f"{len_d0} x (n_rows)  stride0={stride0} stride1={stride1}"
            idle_between = master_config.get('idle_cycles_between_phases', 0)
            if idle_between:
                detail['idle_between_phases'] = f"{idle_between} cycles"
        elif config == '3d':
            base = int(start_address, 2) if set(start_address) <= {'0','1'} else int(start_address, 0)
            first_addr = base
            detail['dims'] = f"{len_d0} x {len_d1} x (n_outer)  stride0={stride0} stride1={stride1} stride2={stride2}"
            last_addr = base  # approximate for 3d
            idle_between = master_config.get('idle_cycles_between_phases', 0)
            if idle_between:
                detail['idle_between_phases'] = f"{idle_between} cycles"

        if first_addr is not None:
            detail['first_addr'] = f"0x{first_addr:08x}  (bank {_bank_of(first_addr)})"
            detail['last_addr']  = f"0x{last_addr:08x}  (bank {_bank_of(last_addr)})"
            detail['transfer']   = f"{n_test} transactions x {data_width // 8} B = {n_test * data_width // 8} B"

        memory_map_entries.append({'label': label, 'pattern': config, 'n': n_test,
                                   'detail': detail})

    # (file_path, n_idle_cycles) -- populated during generation,
    # prepended as idle lines before padding for static start delays.
    pending_start_delays = []

    def _parse_maybe_bin_int(raw_value, default_value):
        """Parse an int or binary/hex/decimal string; return default on failure."""
        if raw_value is None:
            return default_value
        if isinstance(raw_value, int):
            return raw_value
        if isinstance(raw_value, str):
            v = raw_value.strip()
            if not v:
                return default_value
            if set(v) <= {"0", "1"}:
                return int(v, 2)
            try:
                return int(v, 0)
            except ValueError:
                return default_value
        return default_value

    def _normalize_mem_access_type(raw_value, master_name):
        allowed = {
            "random",
            "linear",
            "2d",
            "3d",
            "idle",
            "matmul_phased",
            "multi_linear",
            "bank_group_linear",
            "rw_rowwise",
            "gather_scatter",
            "matmul_tiled_interleave",
            "hotspot_random",
        }
        aliases = {
            "matmul": "matmul_phased",
            "matmul_tiled": "matmul_tiled_interleave",
        }

        if not isinstance(raw_value, str):
            print(
                f"ERROR: {master_name} has invalid mem_access_type={raw_value} "
                f"(type={type(raw_value).__name__}). Allowed: {', '.join(sorted(allowed))}"
            )
            sys.exit(1)

        key = aliases.get(raw_value.strip().lower(), raw_value.strip().lower())
        if key not in allowed:
            print(
                f"ERROR: {master_name} has invalid mem_access_type='{raw_value}'. "
                f"Allowed: {', '.join(sorted(allowed))}"
            )
            sys.exit(1)
        return key

    def _pattern_job_name(pattern_config: dict) -> str:
        """Resolve job name from the mandatory 'job' key."""
        return str(pattern_config.get('job', 'default'))

    def _pattern_wait_for_jobs(pattern_config):
        """Resolve dependency list from the mandatory 'wait_for_jobs' key."""
        raw = pattern_config.get('wait_for_jobs', [])
        if raw is None:
            return []
        if isinstance(raw, list):
            return [str(x) for x in raw]
        return [str(raw)]

    def _warn_if_id_mismatch(master_cfg, expected_idx, master_name):
        raw_id = master_cfg.get("id", expected_idx)
        try:
            cfg_id = int(raw_id)
        except (TypeError, ValueError):
            print(f"WARNING: {master_name} has non-integer id={raw_id}; positional index {expected_idx} is used.")
            return
        if cfg_id != expected_idx:
            print(
                f"WARNING: {master_name} has id={cfg_id} but positional index is {expected_idx}; "
                "stimuli-to-driver mapping is positional."
            )

    def _resolve_n_transactions(master_config: dict, mem_access_type: str, data_width: int, kind: str, local_idx: int) -> int:
        """Resolve n_transactions from explicit field or geometry, depending on pattern."""
        if 'n_transactions' in master_config:
            return int(master_config['n_transactions'])
        access_bytes = max(1, int(data_width // 8))
        if mem_access_type == 'linear':
            length = master_config.get('length')
            if length is not None:
                return int(length)
            raw_region_size = master_config.get('region_size_bytes')
            if raw_region_size is not None:
                region_size = _parse_maybe_bin_int(raw_region_size, None)
                if region_size is not None:
                    return max(0, int(region_size) // access_bytes)
        elif mem_access_type == '2d':
            len_d0 = master_config.get('len_d0')
            len_d1 = master_config.get('len_d1')
            if len_d0 is not None and len_d1 is not None:
                return int(len_d0) * int(len_d1)
        elif mem_access_type == '3d':
            len_d0 = master_config.get('len_d0')
            len_d1 = master_config.get('len_d1')
            len_d2 = master_config.get('len_d2')
            if len_d0 is not None and len_d1 is not None and len_d2 is not None:
                return int(len_d0) * int(len_d1) * int(len_d2)
        elif mem_access_type == 'matmul_phased':
            # For non-random region-based traffic, allow deriving transactions
            # from region size and transaction width.
            raw_region_size = master_config.get('region_size_bytes')
            if raw_region_size is not None:
                region_size = _parse_maybe_bin_int(raw_region_size, None)
                if region_size is not None:
                    return max(0, int(region_size) // access_bytes)
            m = master_config.get('matrix_m')
            n = master_config.get('matrix_n')
            k = master_config.get('matrix_k')
            if m is not None and n is not None and k is not None:
                return int(m) * int(k) + int(k) * int(n) + int(m) * int(n)
        elif mem_access_type == 'multi_linear':
            total = 0
            for reg in master_config.get('regions', []) or []:
                size_v = _parse_maybe_bin_int(reg.get('size_bytes'), 0)
                total += max(0, int(size_v)) // access_bytes
            if total > 0:
                return total
        elif mem_access_type == 'bank_group_linear':
            print(
                f"ERROR: {kind}_{local_idx} mem_access_type='bank_group_linear' "
                "requires explicit 'n_transactions'."
            )
            sys.exit(1)
        elif mem_access_type == 'rw_rowwise':
            n_rows = master_config.get('n_rows')
            rpr = master_config.get('reads_per_row')
            wpr = master_config.get('writes_per_row')
            if n_rows is not None and rpr is not None and wpr is not None:
                return max(0, int(n_rows)) * (max(0, int(rpr)) + max(0, int(wpr)))
        elif mem_access_type == 'gather_scatter':
            chunk = _parse_maybe_bin_int(master_config.get('chunk_bytes'), access_bytes)
            step = max(access_bytes, int(chunk) if chunk is not None else access_bytes)
            total = 0
            for reg in master_config.get('read_regions', []) or []:
                total += max(0, int(_parse_maybe_bin_int(reg.get('size_bytes'), 0))) // step
            wr = master_config.get('write_region', {}) or {}
            total += max(0, int(_parse_maybe_bin_int(wr.get('size_bytes'), 0))) // step
            if total > 0:
                return total
        elif mem_access_type == 'matmul_tiled_interleave':
            tiles = max(1, int(master_config.get('tiles', 1)))
            sched = str(master_config.get('ab_c_schedule', 'A_B_C')).upper().replace('-', '_')
            toks = [t for t in sched.split('_') if t]
            if not toks:
                toks = ['A', 'B', 'C']
            cnt_a = max(1, int(_parse_maybe_bin_int(master_config.get('tile_a_bytes'), access_bytes)) // access_bytes)
            cnt_b = max(1, int(_parse_maybe_bin_int(master_config.get('tile_b_bytes'), access_bytes)) // access_bytes)
            cnt_c = max(1, int(_parse_maybe_bin_int(master_config.get('tile_c_bytes'), access_bytes)) // access_bytes)
            per_tile = 0
            for t in toks:
                if t == 'A':
                    per_tile += cnt_a
                elif t == 'B':
                    per_tile += cnt_b
                elif t == 'C':
                    per_tile += cnt_c
            if per_tile > 0:
                return tiles * per_tile
        elif mem_access_type == 'hotspot_random':
            total = 0
            for reg in master_config.get('hot_regions', []) or []:
                total += max(0, int(_parse_maybe_bin_int(reg.get('size_bytes'), 0))) // access_bytes
            if total > 0:
                return total
        elif mem_access_type == 'idle':
            return 0
        print(f"ERROR: {kind}_{local_idx} has mem_access_type='{mem_access_type}' but no "
              f"'n_transactions' and no geometry fields to derive it from.")
        sys.exit(1)

    def _generate_pattern(
        filepath: Path,
        pattern_config: dict,
        *,
        is_hwpe: bool,
        master_global_idx: int,
        master_local_idx: int,
        n_peers_of_kind: int,
        append: bool,
    ):
        """Generate one pattern segment. append=True opens file in append mode.
        Every pattern always writes a trailing PAUSE (handled by the generator)."""
        nonlocal next_start_id
        data_width = HWPE_WIDTH_FACT * DATA_WIDTH if is_hwpe else DATA_WIDTH
        kind = 'master_hwpe' if is_hwpe else 'master_log'

        master = StimuliGenerator(
            IW, DATA_WIDTH, N_BANKS, TOT_MEM_SIZE, data_width, ADD_WIDTH,
            str(filepath), 0, master_global_idx
        )

        if 'mem_access_type' not in pattern_config:
            print(f"ERROR: {kind}_{master_local_idx} pattern is missing mem_access_type.")
            sys.exit(1)

        config = _normalize_mem_access_type(
            pattern_config['mem_access_type'],
            f"{kind}_{master_local_idx}",
        )
        if 'start_address' in pattern_config:
            start_address = str(pattern_config['start_address'])
        elif config == 'linear' and 'region_base_address' in pattern_config:
            start_address = str(pattern_config['region_base_address'])
        else:
            start_address = '0'

        if 'stride0' in pattern_config:
            stride0 = int(pattern_config['stride0'])
        elif config == 'linear' and 'region_size_bytes' in pattern_config:
            stride0 = 1
        else:
            stride0 = 0
        len_d0 = int(pattern_config.get('len_d0', 0))
        stride1 = int(pattern_config.get('stride1', 0))
        len_d1 = int(pattern_config.get('len_d1', 0))
        stride2 = int(pattern_config.get('stride2', 0))

        total_mem_bytes = int(TOT_MEM_SIZE * 1024)
        access_bytes = max(1, int(data_width // 8))
        default_region_size = total_mem_bytes // max(1, n_peers_of_kind)
        default_region_base = master_local_idx * default_region_size

        region_base = _parse_maybe_bin_int(pattern_config.get('region_base_address'), default_region_base)

        # For non-random region-based patterns, if n_transactions is provided but
        # region_size_bytes is omitted, span a full non-wrapping region that can
        # hold all transactions once at the current transaction width.
        region_size_input = pattern_config.get('region_size_bytes')
        if (
            config in {'linear', 'matmul_phased', 'matmul_tiled_interleave'}
            and region_size_input is None
            and 'n_transactions' in pattern_config
        ):
            region_size_input = int(pattern_config['n_transactions']) * access_bytes

        region_size = _parse_maybe_bin_int(region_size_input, default_region_size)

        region_base = (region_base // access_bytes) * access_bytes
        if region_base >= total_mem_bytes:
            region_base = region_base % total_mem_bytes
        region_size = (max(0, region_size) // access_bytes) * access_bytes
        if region_size <= 0:
            region_size = (default_region_size // access_bytes) * access_bytes
        if region_base + region_size > total_mem_bytes:
            region_size = ((total_mem_bytes - region_base) // access_bytes) * access_bytes

        n_test = _resolve_n_transactions(pattern_config, config, data_width, kind, master_local_idx)
        master.N_TEST = n_test
        # Read/write blocked filtering is pattern-local only.
        read_blocked_local = []
        write_blocked_local = []
        tpct_raw = pattern_config.get('traffic_pct', 100)
        tpct = 100 if tpct_raw is None else int(tpct_raw)

        multi_regions_cfg = []
        for reg in pattern_config.get('regions', []) or []:
            multi_regions_cfg.append({
                'base': _parse_maybe_bin_int(reg.get('base'), 0),
                'size_bytes': _parse_maybe_bin_int(reg.get('size_bytes'), 0),
                'stride_words': int(reg.get('stride_words', 1)),
                'read_pct': reg.get('read_pct'),
            })

        read_regions_cfg = []
        for reg in pattern_config.get('read_regions', []) or []:
            read_regions_cfg.append({
                'base': _parse_maybe_bin_int(reg.get('base'), 0),
                'size_bytes': _parse_maybe_bin_int(reg.get('size_bytes'), 0),
            })
        wr_cfg_raw = pattern_config.get('write_region', {}) or {}
        write_region_cfg = {
            'base': _parse_maybe_bin_int(wr_cfg_raw.get('base'), 0),
            'size_bytes': _parse_maybe_bin_int(wr_cfg_raw.get('size_bytes'), 0),
        }

        hot_regions_cfg = []
        for reg in pattern_config.get('hot_regions', []) or []:
            hot_regions_cfg.append({
                'base': _parse_maybe_bin_int(reg.get('base'), 0),
                'size_bytes': _parse_maybe_bin_int(reg.get('size_bytes'), 0),
                'weight': int(reg.get('weight', 1)),
            })

        if config == 'random':
            next_start_id = master.random_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                region_base=region_base,
                region_size=region_size,
                traffic_pct=tpct,
                traffic_read_pct=pattern_config.get('traffic_read_pct'),
                append=append,
            )
        elif config == 'linear':
            next_start_id = master.linear_gen(
                stride0, start_address, next_start_id,
                read_blocked_local,
                write_blocked_local,
                traffic_pct=tpct,
                traffic_read_pct=pattern_config.get('traffic_read_pct'),
                append=append,
            )
        elif config == '2d':
            next_start_id = master.gen_2d(
                stride0, len_d0, stride1, start_address, next_start_id,
                read_blocked_local,
                write_blocked_local,
                idle_cycles_between_phases=int(pattern_config.get('idle_cycles_between_phases', 0)),
                append=append,
            )
        elif config == '3d':
            next_start_id = master.gen_3d(
                stride0, len_d0, stride1, len_d1, stride2, start_address, next_start_id,
                read_blocked_local,
                write_blocked_local,
                idle_cycles_between_phases=int(pattern_config.get('idle_cycles_between_phases', 0)),
                append=append,
            )
        elif config == 'idle':
            next_start_id = master.idle_gen(next_start_id, append=append)
        elif config == 'matmul_phased':
            if not is_hwpe:
                print(
                    f"WARNING: mem_access_type='matmul_phased' is typically used for HWPE masters; "
                    f"{kind}_{master_local_idx} will still use requested phased behavior."
                )
            min_region_size = 3 * access_bytes
            if region_size < min_region_size:
                print(
                    f"ERROR: {kind}_{master_local_idx} region_size_bytes="
                    f"{region_size} is too small for matmul_phased (minimum {min_region_size})."
                )
                sys.exit(1)
            next_start_id = master.matmul_phased_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                region_base,
                region_size,
                int(pattern_config.get('matmul_ratio_a', 1)),
                int(pattern_config.get('matmul_ratio_b', 1)),
                int(pattern_config.get('matmul_ratio_c', 1)),
                traffic_pct=int(pattern_config.get('traffic_pct', 100)),
                idle_cycles_between_phases=int(pattern_config.get('idle_cycles_between_phases', 0)),
                region_base_address_a=_parse_maybe_bin_int(pattern_config.get('region_base_address_a'), None),
                region_size_bytes_a=_parse_maybe_bin_int(pattern_config.get('region_size_bytes_a'), None),
                region_base_address_b=_parse_maybe_bin_int(pattern_config.get('region_base_address_b'), None),
                region_size_bytes_b=_parse_maybe_bin_int(pattern_config.get('region_size_bytes_b'), None),
                region_base_address_c=_parse_maybe_bin_int(pattern_config.get('region_base_address_c'), None),
                region_size_bytes_c=_parse_maybe_bin_int(pattern_config.get('region_size_bytes_c'), None),
                append=append,
            )
        elif config == 'multi_linear':
            next_start_id = master.multi_linear_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                regions=multi_regions_cfg,
                schedule=pattern_config.get('schedule', 'round_robin'),
                burst_len=int(pattern_config.get('burst_len', 1)),
                traffic_pct=tpct,
                append=append,
            )
        elif config == 'bank_group_linear':
            next_start_id = master.bank_group_linear_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                start_bank=int(pattern_config.get('start_bank', 0)),
                bank_group_span=int(pattern_config.get('bank_group_span', 1)),
                stride_beats=int(pattern_config.get('stride_beats', 1)),
                bank_group_hop=int(pattern_config.get('bank_group_hop', 0)),
                wen=pattern_config.get('wen'),
                traffic_pct=tpct,
                append=append,
            )
        elif config == 'rw_rowwise':
            next_start_id = master.rw_rowwise_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                row_base_address=_parse_maybe_bin_int(pattern_config.get('row_base_address'), region_base),
                row_size_bytes=_parse_maybe_bin_int(pattern_config.get('row_size_bytes'), access_bytes),
                n_rows=int(pattern_config.get('n_rows', 1)),
                row_stride_bytes=_parse_maybe_bin_int(pattern_config.get('row_stride_bytes'), access_bytes),
                reads_per_row=int(pattern_config.get('reads_per_row', 0)),
                writes_per_row=int(pattern_config.get('writes_per_row', 0)),
                traffic_pct=tpct,
                idle_cycles_between_rows=int(pattern_config.get('idle_cycles_between_rows', 0)),
                append=append,
            )
        elif config == 'gather_scatter':
            next_start_id = master.gather_scatter_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                read_regions=read_regions_cfg,
                write_region=write_region_cfg,
                chunk_bytes=_parse_maybe_bin_int(pattern_config.get('chunk_bytes'), access_bytes),
                schedule=pattern_config.get('schedule', '4read_1write'),
                traffic_pct=tpct,
                append=append,
            )
        elif config == 'matmul_tiled_interleave':
            ra = _parse_maybe_bin_int(pattern_config.get('region_base_address_a'), None)
            sa = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_a'), None)
            rb = _parse_maybe_bin_int(pattern_config.get('region_base_address_b'), None)
            sb = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_b'), None)
            rc = _parse_maybe_bin_int(pattern_config.get('region_base_address_c'), None)
            sc = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_c'), None)
            if ra is None or sa is None or rb is None or sb is None or rc is None or sc is None:
                # Fallback to split the combined region into A/B/C thirds.
                n_words = max(3, region_size // access_bytes)
                a_words = max(1, n_words // 3)
                b_words = max(1, n_words // 3)
                c_words = max(1, n_words - a_words - b_words)
                ra = region_base
                sa = a_words * access_bytes
                rb = ra + sa
                sb = b_words * access_bytes
                rc = rb + sb
                sc = c_words * access_bytes
            next_start_id = master.matmul_tiled_interleave_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                region_base_address_a=ra,
                region_size_bytes_a=sa,
                region_base_address_b=rb,
                region_size_bytes_b=sb,
                region_base_address_c=rc,
                region_size_bytes_c=sc,
                tile_a_bytes=_parse_maybe_bin_int(pattern_config.get('tile_a_bytes'), access_bytes),
                tile_b_bytes=_parse_maybe_bin_int(pattern_config.get('tile_b_bytes'), access_bytes),
                tile_c_bytes=_parse_maybe_bin_int(pattern_config.get('tile_c_bytes'), access_bytes),
                tiles=int(pattern_config.get('tiles', 1)),
                ab_c_schedule=pattern_config.get('ab_c_schedule', 'A_B_C'),
                traffic_pct=tpct,
                idle_cycles_between_tiles=int(pattern_config.get('idle_cycles_between_tiles', 0)),
                append=append,
            )
        elif config == 'hotspot_random':
            next_start_id = master.hotspot_random_gen(
                next_start_id,
                read_blocked_local,
                write_blocked_local,
                hot_regions=hot_regions_cfg,
                traffic_pct=tpct,
                traffic_read_pct=pattern_config.get('traffic_read_pct'),
                append=append,
            )

        _record_memory_map(
            kind, master_local_idx,
            pattern_config.get('description', ''),
            config, n_test, data_width, access_bytes,
            region_base, region_size,
            start_address, stride0, len_d0, stride1, len_d1, stride2,
            pattern_config, total_mem_bytes,
        )

    def _generate_master(
        filepath: Path,
        master_config: dict,
        *,
        is_hwpe: bool,
        master_global_idx: int,
        master_local_idx: int,
        n_peers_of_kind: int,
    ):
        """Generate stimulus for a master, supporting single flat pattern or patterns list."""
        data_width = HWPE_WIDTH_FACT * DATA_WIDTH if is_hwpe else DATA_WIDTH

        # Resolve pattern list: either explicit 'patterns' list or a single flat pattern
        if 'patterns' in master_config:
            patterns = master_config['patterns']
            if not patterns:
                kind = 'master_hwpe' if is_hwpe else 'master_log'
                print(f"ERROR: {kind}_{master_local_idx} has empty patterns list.")
                sys.exit(1)
        else:
            # Legacy flat format: treat the master config itself as a single pattern
            patterns = [master_config]

        # Start delay applies to the whole master (prepended before first pattern)
        start_delay = int(master_config.get('start_delay_cycles', 0))
        if start_delay > 0:
            pending_start_delays.append((filepath, start_delay, data_width))

        # For each pattern with wait_for_jobs, prepend a synthetic idle+PAUSE that acts as
        # the blocking fence. The pattern's own trailing PAUSE is always mask=0 (free
        # pass), so fence_idx advances immediately after the real work is done.
        # This separates "I am done" (trailing PAUSE, free) from "I may start" (idle
        # gate, blocking), giving resume_i a single clean meaning: start your next job.
        dw = HWPE_WIDTH_FACT * DATA_WIDTH if is_hwpe else DATA_WIDTH
        first_written = False
        for p_idx, pattern_config in enumerate(patterns):
            if _pattern_wait_for_jobs(pattern_config):
                # Synthetic idle+PAUSE gates this pattern
                _idle = StimuliGenerator(IW, DATA_WIDTH, N_BANKS, TOT_MEM_SIZE,
                                         dw, ADD_WIDTH, str(filepath), 0, master_global_idx)
                _idle.N_TEST = 0
                _idle.idle_gen(next_start_id, append=first_written)
                first_written = True
            _generate_pattern(
                filepath,
                pattern_config,
                is_hwpe=is_hwpe,
                master_global_idx=master_global_idx,
                master_local_idx=master_local_idx,
                n_peers_of_kind=n_peers_of_kind,
                append=first_written,
            )
            first_written = True

    global_idx = 0

    # Generate LOG masters (CORE, DMA, EXT) in order
    for i in range(N_LOG):
        if i < N_CORE:
            if CORE_ZERO_FLAG:
                global_idx += 1
                continue
        elif i < N_CORE + N_DMA:
            if DMA_ZERO_FLAG:
                global_idx += 1
                continue
        else:
            if EXT_ZERO_FLAG:
                global_idx += 1
                continue

        master_cfg = log_masters[i]
        _warn_if_id_mismatch(master_cfg, i, f"master_log_{i}")
        _generate_master(
            stimuli_dir / f"master_log_{i}.txt",
            master_cfg,
            is_hwpe=False,
            master_global_idx=global_idx,
            master_local_idx=i,
            n_peers_of_kind=max(1, N_LOG),
        )
        global_idx += 1

    # Generate HWPE masters
    for hw_idx in range(N_HWPE):
        if HWPE_ZERO_FLAG:
            global_idx += 1
            continue
        master_cfg = hwpe_masters[hw_idx]
        _warn_if_id_mismatch(master_cfg, hw_idx, f"master_hwpe_{hw_idx}")
        _generate_master(
            stimuli_dir / f"master_hwpe_{hw_idx}.txt",
            master_cfg,
            is_hwpe=True,
            master_global_idx=global_idx,
            master_local_idx=hw_idx,
            n_peers_of_kind=max(1, N_HWPE),
        )
        global_idx += 1

    print("STEP 0 COMPLETED: generate stimuli files")

    # -----------------------------------------------------------------------
    # Compute FENCE_MASKS and emit fence_masks.mk
    #
    # Fence slot f corresponds to the PAUSE before pattern f in the stimulus
    # file (i.e. between pattern f-1 and pattern f). The mask at slot f holds
    # the set of drivers that must have passed fence f before this driver can
    # resume from that PAUSE.
    #
    # For a master with N patterns, there are N fence slots (slot 0 = before
    # pattern 0, slot f = before pattern f). The wait_for_jobs of pattern f defines
    # the mask at fence slot f.
    #
    # Legacy flat masters (no 'patterns' key) are treated as single-pattern
    # masters: one fence slot (slot 0) from the top-level wait_for_jobs field.
    # -----------------------------------------------------------------------
    N_DRIVERS = N_LOG + N_HWPE

    def _patterns_of(master_config):
        """Return the list of pattern configs for a master."""
        if 'patterns' in master_config:
            return master_config['patterns']
        return [master_config]

    # Build job->driver map: every pattern of every driver registers its job.
    # This allows wait_for_jobs to reference any job, not just first patterns.
    # A job may be associated with multiple drivers (e.g. 8 cores all in softmax_t0).
    job_to_drivers = {}
    all_masters = [(m, False) for m in log_masters] + [(m, True) for m in hwpe_masters]
    for i, (m, _) in enumerate(all_masters):
        for pat in _patterns_of(m):
            job = _pattern_job_name(pat)
            if i not in job_to_drivers.get(job, []):
                job_to_drivers.setdefault(job, []).append(i)

    # Build job->pattern_index map: for each job, which pattern index within
    # each driver corresponds to that job. Used to compute FENCE_REQ_LEVELS.
    # job_pattern_idx[job][driver] = pattern index of that job in that driver
    job_pattern_idx = {}
    for i, (m, _) in enumerate(all_masters):
        for p_idx, pat in enumerate(_patterns_of(m)):
            job = _pattern_job_name(pat)
            job_pattern_idx.setdefault(job, {})[i] = p_idx

    def _resolve_wait_mask(wait_for_jobs_list):
        mask = 0
        for dep_job in wait_for_jobs_list:
            for dep_drv in job_to_drivers.get(str(dep_job), []):
                mask |= (1 << dep_drv)
        return mask

    # Precompute per-driver fence_idx value after finishing pattern p:
    # = number of fences (synthetic idle gates + trailing PAUSEs) passed up to and
    #   including the trailing PAUSE of pattern p.
    def _fence_idx_after_pattern(drv_idx, pat_idx):
        pats = _patterns_of(all_masters[drv_idx][0])
        # Count synthetic idle gates for patterns 0..pat_idx (those with wait_for_jobs)
        n_gates = sum(1 for k in range(pat_idx + 1) if _pattern_wait_for_jobs(pats[k]))
        # Plus trailing PAUSEs for patterns 0..pat_idx
        n_trailing = pat_idx + 1
        return n_gates + n_trailing

    def _resolve_req_levels(wait_for_jobs_list):
        """Required fence_idx[j] = fence_idx value of j after finishing pattern p_j."""
        levels = [0] * N_DRIVERS
        for dep_job in wait_for_jobs_list:
            for dep_drv in job_to_drivers.get(str(dep_job), []):
                p_idx = job_pattern_idx.get(str(dep_job), {}).get(dep_drv, 0)
                levels[dep_drv] = _fence_idx_after_pattern(dep_drv, p_idx)
        return levels

    # Build per-driver fence mask and req_level lists.
    # Each pattern with wait_for_jobs gets a synthetic idle gate (mask = wait_for_jobs) before it.
    # Trailing PAUSEs always have mask=0 (free pass — just advance fence_idx).
    # Fences are enumerated in file order: for each pattern p:
    #   if p has wait_for_jobs: synthetic idle fence (mask = wait_for_jobs of p)
    #   trailing PAUSE fence (mask = 0)
    fence_masks = []
    req_levels = []
    for i, (m, _) in enumerate(all_masters):
        patterns = _patterns_of(m)
        per_masks  = []
        per_levels = []
        for pat in patterns:
            wait_for_jobs = _pattern_wait_for_jobs(pat)
            if wait_for_jobs:
                # Synthetic idle gate: blocking fence
                per_masks.append(_resolve_wait_mask(wait_for_jobs))
                per_levels.append(_resolve_req_levels(wait_for_jobs))
            # Trailing PAUSE: free pass, just signals completion
            per_masks.append(0)
            per_levels.append([0] * N_DRIVERS)
        fence_masks.append(per_masks)
        req_levels.append(per_levels)

    max_fences = max((len(fm) for fm in fence_masks), default=1)

    # Pad to max_fences
    for i in range(N_DRIVERS):
        while len(fence_masks[i]) < max_fences:
            fence_masks[i].append(0)
        while len(req_levels[i]) < max_fences:
            req_levels[i].append([0] * N_DRIVERS)

    # FENCE_REQ_LEVELS[N_DRIVERS][MAX_FENCES][N_DRIVERS] — int unsigned
    # Pack FENCE_REQ_LEVELS as FENCE_REQ_LEVELS_PACKED[i][f] = N_DRIVERS*LEVEL_BITS-bit vector.
    # Bits [j*LEVEL_BITS+LEVEL_BITS-1:j*LEVEL_BITS] = required fence_idx[j].
    max_req_level = 0
    for i in range(N_DRIVERS):
        for f in range(max_fences):
            for j in range(N_DRIVERS):
                max_req_level = max(max_req_level, int(req_levels[i][f][j]))
    # Derive minimum LEVEL_BITS to represent max_req_level (at least 1 bit).
    LEVEL_BITS = max(1, max_req_level.bit_length())
    max_level_val = (1 << LEVEL_BITS) - 1

    # SV array depth is MAX_FENCES = 2^LEVEL_BITS; pad to this depth.
    array_depth = 2 ** LEVEL_BITS
    for i in range(N_DRIVERS):
        while len(fence_masks[i]) < array_depth:
            fence_masks[i].append(0)
        while len(req_levels[i]) < array_depth:
            req_levels[i].append([0] * N_DRIVERS)

    # Emit SV literals
    hex_width = max(1, (N_DRIVERS + 3) // 4)
    per_driver_literals = []
    for i in range(N_DRIVERS):
        slot_literals = [f"{N_DRIVERS}'h{fence_masks[i][f]:0{hex_width}x}" for f in range(array_depth)]
        per_driver_literals.append("'{" + ", ".join(slot_literals) + "}")
    fence_masks_param = "'{" + ", ".join(per_driver_literals) + "}"

    packed_width = N_DRIVERS * LEVEL_BITS
    packed_hex_digits = (packed_width + 3) // 4
    req_driver_literals = []
    for i in range(N_DRIVERS):
        fence_literals = []
        for f in range(array_depth):
            val = 0
            for j in range(N_DRIVERS):
                val |= (req_levels[i][f][j] & max_level_val) << (j * LEVEL_BITS)
            fence_literals.append(f"{packed_width}'h{val:0{packed_hex_digits}x}")
        req_driver_literals.append("'{" + ", ".join(fence_literals) + "}")
    fence_req_levels_packed_param = "'{" + ", ".join(req_driver_literals) + "}"

    if args.emit_phases_mk:
        phases_mk_path = Path(args.emit_phases_mk)
        phases_mk_path.parent.mkdir(parents=True, exist_ok=True)
        phases_mk_path.write_text(
            "# Auto-generated by main.py - DO NOT EDIT MANUALLY\n"
            "# Per-driver per-fence dependency data for tb_hci.sv.\n"
            f"# Drivers 0..{N_LOG-1} = narrow masters (core/dma/ext), {N_LOG}..{N_DRIVERS-1} = HWPE masters.\n"
            f"# fence f = PAUSE after pattern f; fence_idx[i]==k means i completed k patterns.\n"
            f"# FENCE_MASKS[i][f][j]=1: j is a dependency of i at fence f.\n"
            f"# FENCE_REQ_LEVELS_PACKED[i][f]: packed {packed_width}-bit vector, bits [j*LEVEL_BITS+LEVEL_BITS-1:j*LEVEL_BITS] = min fence_idx[j].\n"
            f"# LEVEL_BITS: minimum bits to encode the max required fence_idx ({max_req_level}) for this workload.\n"
            f"# Array depth and packed field width are both derived as 2^LEVEL_BITS.\n"
            f"LEVEL_BITS := {LEVEL_BITS}\n"
            f"FENCE_MASKS_PARAM := {fence_masks_param}\n"
            f"FENCE_REQ_LEVELS_PACKED_PARAM := {fence_req_levels_packed_param}\n",
            encoding='utf-8',
        )
        print(f"FENCE_MASKS.MK written: {phases_mk_path}")

    # -----------------------------------------------------------------------
    # Build and emit memory map report
    # -----------------------------------------------------------------------
    INTERCO_TYPE = str(hw_params.get('INTERCO_TYPE', 'HCI')).strip().upper()
    if INTERCO_TYPE not in {"LOG", "MUX", "HCI"}:
        INTERCO_TYPE = "HCI"
    DW_NARROW = int(DATA_WIDTH)
    DW_WIDE = int(HWPE_WIDTH_FACT * DATA_WIDTH)
    N_NARROW_HCI_CFG = int(
        N_CORE_CFG + N_DMA_CFG + N_EXT_CFG
        + (N_HWPE_CFG * HWPE_WIDTH_FACT if INTERCO_TYPE == "LOG" else 0)
    )
    N_WIDE_HCI_CFG = int(N_HWPE_CFG if INTERCO_TYPE == "HCI" else (1 if INTERCO_TYPE == "MUX" else 0))
    N_MASTER_PORTS_CFG = int(N_NARROW_HCI_CFG + N_WIDE_HCI_CFG)

    def _driver_name(driver_idx):
        if driver_idx < N_LOG:
            return _narrow_driver_name(driver_idx)
        return f"hwpe_{driver_idx - N_LOG}"

    def _resolve_regions(pattern_config, mem_access_type, is_hwpe, local_idx, n_peers):
        data_width = HWPE_WIDTH_FACT * DATA_WIDTH if is_hwpe else DATA_WIDTH
        access_bytes = max(1, int(data_width // 8))
        total_mem_bytes = int(TOT_MEM_SIZE * 1024)
        default_region_size = total_mem_bytes // max(1, n_peers)
        default_region_base = local_idx * default_region_size

        region_base = _parse_maybe_bin_int(pattern_config.get('region_base_address'), default_region_base)
        region_size = _parse_maybe_bin_int(pattern_config.get('region_size_bytes'), default_region_size)

        region_base = (region_base // access_bytes) * access_bytes
        if region_base >= total_mem_bytes:
            region_base = region_base % total_mem_bytes
        region_size = (max(0, region_size) // access_bytes) * access_bytes
        if region_size <= 0:
            region_size = (default_region_size // access_bytes) * access_bytes
        if region_base + region_size > total_mem_bytes:
            region_size = ((total_mem_bytes - region_base) // access_bytes) * access_bytes

        if region_size <= 0:
            return []

        if mem_access_type == 'idle':
            return []
        if mem_access_type == 'multi_linear':
            regions = []
            for idx, reg in enumerate(pattern_config.get('regions', []) or []):
                base = _parse_maybe_bin_int(reg.get('base'), region_base)
                size = _parse_maybe_bin_int(reg.get('size_bytes'), region_size)
                base = (base // access_bytes) * access_bytes
                if base >= total_mem_bytes:
                    base = base % total_mem_bytes
                size = (max(0, size) // access_bytes) * access_bytes
                if base + size > total_mem_bytes:
                    size = ((total_mem_bytes - base) // access_bytes) * access_bytes
                if size <= 0:
                    continue
                rpct = reg.get('read_pct')
                if rpct is None:
                    lbl = f"R{idx}"
                else:
                    lbl = f"R{idx}({'read' if int(rpct) >= 50 else 'write'})"
                regions.append({
                    'label': lbl,
                    'base': base,
                    'size': size,
                    'end': base + size - 1,
                })
            return regions
        if mem_access_type == 'bank_group_linear':
            span = max(1, int(pattern_config.get('bank_group_span', 1)))
            start_bank = int(pattern_config.get('start_bank', 0)) % max(1, int(N_BANKS))
            n_tx = _parse_maybe_bin_int(pattern_config.get('n_transactions'), 1)
            n_tx = max(1, int(n_tx))
            rows = max(1, math.ceil(n_tx / span))
            size = min(total_mem_bytes, rows * span * access_bytes)
            base = (start_bank * access_bytes) % max(1, total_mem_bytes)
            if base + size > total_mem_bytes:
                size = max(access_bytes, total_mem_bytes - base)
            return [{
                'label': 'bank_group',
                'base': base,
                'size': size,
                'end': base + size - 1,
            }]
        if mem_access_type == 'rw_rowwise':
            row_base = _parse_maybe_bin_int(pattern_config.get('row_base_address'), region_base)
            row_size = _parse_maybe_bin_int(pattern_config.get('row_size_bytes'), access_bytes)
            n_rows = max(1, int(pattern_config.get('n_rows', 1)))
            row_stride = _parse_maybe_bin_int(pattern_config.get('row_stride_bytes'), row_size)
            base = (row_base // access_bytes) * access_bytes
            if base >= total_mem_bytes:
                base = base % total_mem_bytes
            size = ((max(0, row_stride) * max(0, n_rows - 1)) + max(0, row_size))
            size = (size // access_bytes) * access_bytes
            if base + size > total_mem_bytes:
                size = ((total_mem_bytes - base) // access_bytes) * access_bytes
            if size <= 0:
                size = access_bytes
            return [{
                'label': 'rowwise',
                'base': base,
                'size': size,
                'end': base + size - 1,
            }]
        if mem_access_type == 'gather_scatter':
            regions = []
            for idx, reg in enumerate(pattern_config.get('read_regions', []) or []):
                base = _parse_maybe_bin_int(reg.get('base'), region_base)
                size = _parse_maybe_bin_int(reg.get('size_bytes'), 0)
                base = (base // access_bytes) * access_bytes
                if base >= total_mem_bytes:
                    base = base % total_mem_bytes
                size = (max(0, size) // access_bytes) * access_bytes
                if base + size > total_mem_bytes:
                    size = ((total_mem_bytes - base) // access_bytes) * access_bytes
                if size <= 0:
                    continue
                regions.append({
                    'label': f"gather_{idx}(read)",
                    'base': base,
                    'size': size,
                    'end': base + size - 1,
                })
            wr = pattern_config.get('write_region', {}) or {}
            wb = _parse_maybe_bin_int(wr.get('base'), region_base)
            ws = _parse_maybe_bin_int(wr.get('size_bytes'), 0)
            wb = (wb // access_bytes) * access_bytes
            if wb >= total_mem_bytes:
                wb = wb % total_mem_bytes
            ws = (max(0, ws) // access_bytes) * access_bytes
            if wb + ws > total_mem_bytes:
                ws = ((total_mem_bytes - wb) // access_bytes) * access_bytes
            if ws > 0:
                regions.append({
                    'label': 'scatter(write)',
                    'base': wb,
                    'size': ws,
                    'end': wb + ws - 1,
                })
            return regions
        if mem_access_type == 'hotspot_random':
            regions = []
            for idx, reg in enumerate(pattern_config.get('hot_regions', []) or []):
                base = _parse_maybe_bin_int(reg.get('base'), region_base)
                size = _parse_maybe_bin_int(reg.get('size_bytes'), 0)
                base = (base // access_bytes) * access_bytes
                if base >= total_mem_bytes:
                    base = base % total_mem_bytes
                size = (max(0, size) // access_bytes) * access_bytes
                if base + size > total_mem_bytes:
                    size = ((total_mem_bytes - base) // access_bytes) * access_bytes
                if size <= 0:
                    continue
                regions.append({
                    'label': f"hot_{idx}",
                    'base': base,
                    'size': size,
                    'end': base + size - 1,
                })
            return regions
        if mem_access_type == 'matmul_tiled_interleave':
            ra = _parse_maybe_bin_int(pattern_config.get('region_base_address_a'), None)
            sa = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_a'), None)
            rb = _parse_maybe_bin_int(pattern_config.get('region_base_address_b'), None)
            sb = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_b'), None)
            rc = _parse_maybe_bin_int(pattern_config.get('region_base_address_c'), None)
            sc = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_c'), None)
            regions = []
            if ra is not None and sa is not None and rb is not None and sb is not None and rc is not None and sc is not None:
                sub_defs = [
                    ('A(read)', ra, sa),
                    ('B(read)', rb, sb),
                    ('C(write)', rc, sc),
                ]
            else:
                n_words = max(3, region_size // access_bytes)
                a_words = max(1, n_words // 3)
                b_words = max(1, n_words // 3)
                c_words = max(1, n_words - a_words - b_words)
                sub_defs = [
                    ('A(read)', region_base, a_words * access_bytes),
                    ('B(read)', region_base + a_words * access_bytes, b_words * access_bytes),
                    ('C(write)', region_base + (a_words + b_words) * access_bytes, c_words * access_bytes),
                ]
            for label, base_raw, size_raw in sub_defs:
                base = (int(base_raw) // access_bytes) * access_bytes
                if base >= total_mem_bytes:
                    base = base % total_mem_bytes
                size = (max(0, int(size_raw)) // access_bytes) * access_bytes
                if base + size > total_mem_bytes:
                    size = ((total_mem_bytes - base) // access_bytes) * access_bytes
                if size > 0:
                    regions.append({
                        'label': label,
                        'base': base,
                        'size': size,
                        'end': base + size - 1,
                    })
            return regions

        if mem_access_type != 'matmul_phased':
            return [{
                'label': 'region',
                'base': region_base,
                'size': region_size,
                'end': region_base + region_size - 1,
            }]

        ra = _parse_maybe_bin_int(pattern_config.get('region_base_address_a'), None)
        sa = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_a'), None)
        rb = _parse_maybe_bin_int(pattern_config.get('region_base_address_b'), None)
        sb = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_b'), None)
        rc = _parse_maybe_bin_int(pattern_config.get('region_base_address_c'), None)
        sc = _parse_maybe_bin_int(pattern_config.get('region_size_bytes_c'), None)

        regions = []
        if ra is not None and sa is not None:
            sub_defs = [
                ('A(read)', ra, sa),
                ('B(read)', rb if rb is not None else ra, sb if sb is not None else sa),
                ('C(write)', rc if rc is not None else ra, sc if sc is not None else sa),
            ]
            for label, base_raw, size_raw in sub_defs:
                base = (int(base_raw) // access_bytes) * access_bytes
                if base >= total_mem_bytes:
                    base = base % total_mem_bytes
                size = (max(0, int(size_raw)) // access_bytes) * access_bytes
                if base + size > total_mem_bytes:
                    size = ((total_mem_bytes - base) // access_bytes) * access_bytes
                if size > 0:
                    regions.append({
                        'label': label,
                        'base': base,
                        'size': size,
                        'end': base + size - 1,
                    })
            return regions

        n_words = region_size // access_bytes
        if n_words < 3:
            return [{
                'label': 'region',
                'base': region_base,
                'size': region_size,
                'end': region_base + region_size - 1,
            }]
        a_words = max(1, n_words // 3)
        b_words = max(1, n_words // 3)
        c_words = n_words - a_words - b_words
        sub_regions = [
            ('A(read)', region_base, a_words * access_bytes),
            ('B(read)', region_base + a_words * access_bytes, b_words * access_bytes),
            ('C(write)', region_base + (a_words + b_words) * access_bytes, c_words * access_bytes),
        ]
        for label, base, size in sub_regions:
            if size <= 0:
                continue
            regions.append({
                'label': label,
                'base': base,
                'size': size,
                'end': base + size - 1,
            })
        return regions

    def _estimate_pattern_cycles(pattern_config, _mem_access_type, n_test, _txn_bytes):
        # Temporal model intentionally follows emitted traffic only:
        # one unit per transaction plus req=0 idles from traffic_pct shaping.
        # No absolute/phase/tile/row cycle estimation is applied here.
        base = max(0, int(n_test))
        tpct = pattern_config.get('traffic_pct')
        n_idles_per_req = 0
        if tpct is not None:
            tp = max(1, min(100, int(tpct)))
            n_idles_per_req = 0 if tp >= 100 else int(round((100 - tp) / tp))
        return int(base * (1 + n_idles_per_req))

    pattern_nodes = []
    node_idx_by_driver_pattern = {}
    job_to_nodes = {}
    driver_last_node = {}

    for drv_idx, (master_cfg, is_hwpe) in enumerate(all_masters):
        patterns = _patterns_of(master_cfg)
        local_idx = drv_idx - N_LOG if is_hwpe else drv_idx
        data_width = HWPE_WIDTH_FACT * DATA_WIDTH if is_hwpe else DATA_WIDTH
        kind = 'master_hwpe' if is_hwpe else 'master_log'
        n_peers = max(1, N_HWPE if is_hwpe else N_LOG)
        start_delay = int(master_cfg.get('start_delay_cycles', 0))
        for p_idx, pat in enumerate(patterns):
            raw_type = pat.get('mem_access_type', 'idle')
            mem_access_type = _normalize_mem_access_type(raw_type, f"{kind}_{local_idx}")
            n_test = _resolve_n_transactions(pat, mem_access_type, data_width, kind, local_idx)
            declared_wait_for_jobs = _pattern_wait_for_jobs(pat)
            # Timeline view follows declared dependencies from workload.json.
            effective_wait_for_jobs = declared_wait_for_jobs
            node = {
                'node_idx': len(pattern_nodes),
                'driver_idx': drv_idx,
                'driver_name': _driver_name(drv_idx),
                'is_hwpe': is_hwpe,
                'local_idx': local_idx,
                'pattern_idx': p_idx,
                'description': str(pat.get('description', '')).strip(),
                'job': _pattern_job_name(pat),
                'wait_for_jobs_declared': declared_wait_for_jobs,
                'wait_for_jobs_effective': effective_wait_for_jobs,
                'n_transactions': int(n_test),
                'cycles': int(_estimate_pattern_cycles(pat, mem_access_type, n_test, int(data_width // 8))),
                'mem_access_type': mem_access_type,
                'traffic_read_pct': pat.get('traffic_read_pct'),
                'txn_bytes': int(data_width // 8),
                'start_delay': start_delay if p_idx == 0 else 0,
                'regions': _resolve_regions(pat, mem_access_type, is_hwpe, local_idx, n_peers),
            }
            pattern_nodes.append(node)
            node_idx_by_driver_pattern[(drv_idx, p_idx)] = node['node_idx']
            job_to_nodes.setdefault(node['job'], []).append(node['node_idx'])
            driver_last_node[drv_idx] = node['node_idx']

    n_nodes = len(pattern_nodes)
    preds = [set() for _ in range(n_nodes)]
    succs = [set() for _ in range(n_nodes)]
    mux_serialization_applied = False
    mux_phase_order = []

    def _add_edge(src, dst):
        if src == dst or src < 0 or dst < 0:
            return
        if src not in preds[dst]:
            preds[dst].add(src)
            succs[src].add(dst)

    for node in pattern_nodes:
        n_idx = node['node_idx']
        drv_idx = node['driver_idx']
        p_idx = node['pattern_idx']
        if p_idx > 0:
            _add_edge(node_idx_by_driver_pattern[(drv_idx, p_idx - 1)], n_idx)
        for dep_job in node['wait_for_jobs_effective']:
            for dep_idx in job_to_nodes.get(dep_job, []):
                _add_edge(dep_idx, n_idx)

    if INTERCO_TYPE == "MUX":
        # Match tb_hci MUX semantics in the temporal model:
        # serialize HWPE execution by job order, and by HWPE ID within a job.
        hwpe_nodes = [n for n in pattern_nodes if n['is_hwpe']]
        if hwpe_nodes:
            job_first_seen = {}
            for n in sorted(hwpe_nodes, key=lambda x: (x['pattern_idx'], x['local_idx'], x['node_idx'])):
                job_first_seen.setdefault(n['job'], len(job_first_seen))

            job_preds = {jb: set() for jb in job_first_seen}
            job_succs = {jb: set() for jb in job_first_seen}
            for n in hwpe_nodes:
                cur = n['job']
                for dep_job in n['wait_for_jobs_effective']:
                    dep = str(dep_job)
                    if dep in job_first_seen and dep != cur:
                        job_preds[cur].add(dep)
                        job_succs[dep].add(cur)

            phase_indeg = {jb: len(job_preds[jb]) for jb in job_first_seen}
            phase_ready = sorted([jb for jb, deg in phase_indeg.items() if deg == 0],
                                 key=lambda jb: job_first_seen[jb])
            mux_phase_order = []
            while phase_ready:
                cur = phase_ready.pop(0)
                mux_phase_order.append(cur)
                for nxt in sorted(job_succs[cur], key=lambda jb: job_first_seen[jb]):
                    phase_indeg[nxt] -= 1
                    if phase_indeg[nxt] == 0:
                        phase_ready.append(nxt)
                phase_ready.sort(key=lambda jb: job_first_seen[jb])
            if len(mux_phase_order) != len(job_first_seen):
                mux_phase_order = sorted(job_first_seen.keys(), key=lambda jb: job_first_seen[jb])

            phase_rank = {ph: i for i, ph in enumerate(mux_phase_order)}
            hwpe_sorted = sorted(
                hwpe_nodes,
                key=lambda n: (
                    phase_rank.get(n['job'], 10 ** 9),
                    n['local_idx'],
                    n['pattern_idx'],
                    n['node_idx'],
                ),
            )
            for i in range(1, len(hwpe_sorted)):
                _add_edge(hwpe_sorted[i - 1]['node_idx'], hwpe_sorted[i]['node_idx'])
            mux_serialization_applied = True

    indeg = [len(preds[i]) for i in range(n_nodes)]
    ready = [i for i, d in enumerate(indeg) if d == 0]
    ready.sort(key=lambda i: (pattern_nodes[i]['driver_idx'], pattern_nodes[i]['pattern_idx']))
    topo_order = []
    while ready:
        cur = ready.pop(0)
        topo_order.append(cur)
        for nxt in sorted(succs[cur]):
            indeg[nxt] -= 1
            if indeg[nxt] == 0:
                ready.append(nxt)
        ready.sort(key=lambda i: (pattern_nodes[i]['driver_idx'], pattern_nodes[i]['pattern_idx']))

    schedule_has_cycle = len(topo_order) != n_nodes
    if schedule_has_cycle:
        topo_order = list(range(n_nodes))

    node_start = [0 for _ in range(n_nodes)]
    node_end = [0 for _ in range(n_nodes)]
    for _ in range(max(1, n_nodes + 1)):
        changed = False
        for n_idx in topo_order:
            dep_end = max((node_end[p] for p in preds[n_idx]), default=0)
            start_time = max(int(pattern_nodes[n_idx]['start_delay']), dep_end)
            end_time = start_time + max(0, int(pattern_nodes[n_idx]['cycles']))
            if start_time != node_start[n_idx] or end_time != node_end[n_idx]:
                node_start[n_idx] = start_time
                node_end[n_idx] = end_time
                changed = True
        if not changed:
            break

    for n_idx, node in enumerate(pattern_nodes):
        node['start_cycle'] = int(node_start[n_idx])
        node['end_cycle'] = int(node_end[n_idx])

    total_cycles = max((n['end_cycle'] for n in pattern_nodes), default=0)

    driver_windows = {}
    for node in pattern_nodes:
        w = driver_windows.setdefault(node['driver_idx'], {
            'driver_idx': node['driver_idx'],
            'name': node['driver_name'],
            'is_hwpe': node['is_hwpe'],
            'start': node['start_cycle'],
            'end': node['end_cycle'],
        })
        w['start'] = min(w['start'], node['start_cycle'])
        w['end'] = max(w['end'], node['end_cycle'])

    regions_timeline = {}
    for node in pattern_nodes:
        for reg in node['regions']:
            reg_key = (reg['base'], reg['size'], reg['label'])
            entry = regions_timeline.setdefault(reg_key, {
                'base': reg['base'],
                'size': reg['size'],
                'end': reg['end'],
                'label': reg['label'],
                'accesses': [],
            })
            entry['accesses'].append({
                'driver_idx': node['driver_idx'],
                'driver_name': node['driver_name'],
                'job': node['job'],
                'start': node['start_cycle'],
                'end': node['end_cycle'],
                'pattern_idx': node['pattern_idx'],
                'description': node['description'],
            })
    for reg in regions_timeline.values():
        reg['lifetime_start'] = min((a['start'] for a in reg['accesses']), default=0)
        reg['lifetime_end'] = max((a['end'] for a in reg['accesses']), default=0)

    # -----------------------------------------------------------------------
    # Build memory_map.txt
    # -----------------------------------------------------------------------
    memory_map_path = generated_dir / 'memory_map.txt'
    write_memory_map_txt(
        memory_map_path=memory_map_path,
        total_mem_size_kib=TOT_MEM_SIZE,
        n_banks=N_BANKS,
        data_width=DATA_WIDTH,
        hwpe_data_width=HWPE_WIDTH_FACT * DATA_WIDTH,
        n_core_cfg=N_CORE_CFG,
        n_dma_cfg=N_DMA_CFG,
        n_ext_cfg=N_EXT_CFG,
        n_log_cfg=N_LOG_CFG,
        n_hwpe_cfg=N_HWPE_CFG,
        interco_type=INTERCO_TYPE,
        dw_narrow=DW_NARROW,
        dw_wide=DW_WIDE,
        n_narrow_hci_cfg=N_NARROW_HCI_CFG,
        n_wide_hci_cfg=N_WIDE_HCI_CFG,
        memory_map_entries=memory_map_entries,
        job_to_drivers=job_to_drivers,
        driver_name_fn=_driver_name,
        n_drivers=N_DRIVERS,
        fence_masks=fence_masks,
        total_cycles=total_cycles,
        mux_serialization_applied=mux_serialization_applied,
        mux_phase_order=mux_phase_order,
        schedule_has_cycle=schedule_has_cycle,
        driver_windows=driver_windows,
        pattern_nodes=pattern_nodes,
        regions_timeline=regions_timeline,
    )
    print(f"Memory map written: {memory_map_path}")

    # -----------------------------------------------------------------------
    # Build dataflow.html (simple SVG timeline view)
    # -----------------------------------------------------------------------
    dataflow_path = generated_dir / 'dataflow.html'
    write_memory_lifetime_html(
        memory_lifetime_path=dataflow_path,
        pattern_nodes=pattern_nodes,
        driver_windows=driver_windows,
        regions_timeline=regions_timeline,
        total_cycles=total_cycles,
        mux_serialization_applied=mux_serialization_applied,
        mux_phase_order=mux_phase_order,
        schedule_has_cycle=schedule_has_cycle,
        driver_name_fn=_driver_name,
        interco_type=INTERCO_TYPE,
        n_core_cfg=N_CORE_CFG,
        n_dma_cfg=N_DMA_CFG,
        n_ext_cfg=N_EXT_CFG,
        n_hwpe_cfg=N_HWPE_CFG,
        dw_narrow=DW_NARROW,
        dw_wide=DW_WIDE,
        n_narrow_hci_cfg=N_NARROW_HCI_CFG,
        n_wide_hci_cfg=N_WIDE_HCI_CFG,
        n_banks=N_BANKS,
    )
    print(f"Dataflow plot written: {dataflow_path}")

    # -----------------------------------------------------------------------
    # Apply per-master start delays
    # -----------------------------------------------------------------------
    for fpath, delay, dw in pending_start_delays:
        if fpath.exists():
            idle_line = "0 " + "0" * IW + " 0 " + "0" * dw + " " + "0" * ADD_WIDTH + "\n"
            original = fpath.read_text(encoding='ascii')
            fpath.write_text(idle_line * delay + original, encoding='ascii')

    print("STEP 1 COMPLETED: generate documents and apply start delays to stimuli")

    # -----------------------------------------------------------------------
    # Golden vectors
    # -----------------------------------------------------------------------
    if args.golden:
        golden_dir = (generated_dir / 'golden').resolve()
        golden_dir.mkdir(parents=True, exist_ok=True)

        for stim_path in sorted(stimuli_dir.glob('master_*.txt')):
            try:
                text = stim_path.read_text(encoding='ascii')
            except OSError:
                continue

            mem = {}
            out_lines = []
            for raw_line in text.splitlines():
                line = raw_line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) != 5:
                    continue
                req_s, id_s, wen_s, data_s, add_s = parts
                if req_s != '1':
                    continue
                if wen_s == '0':
                    mem[add_s] = data_s
                    continue
                exp_s = mem.get(add_s, '1' * len(data_s))
                out_lines.append(f"{id_s} {add_s} {exp_s}")

            (golden_dir / f"golden_{stim_path.name}").write_text(
                "\n".join(out_lines) + ("\n" if out_lines else ""), encoding='ascii'
            )
        print("STEP 2 COMPLETED: golden vectors")


if __name__ == '__main__':
    main()
