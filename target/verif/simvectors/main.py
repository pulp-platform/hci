"""Stimuli generator (reads JSON configs in `verif/config`).

This script is invoked by the top-level Makefile and expects three
JSON config files: workload, testbench and hardware. It produces
cycle-accurate stimuli in `verif/simvectors/generated/stimuli`.

Each stimuli file has one line per simulation cycle:
  req(1b) id(IWb) wen(1b) data(Nb) add(Ab)
"""

import json
import math
import sys
import html
from pathlib import Path
import argparse

code_directory = Path(__file__).resolve().parent

try:
    from hci_stimuli import StimuliGenerator, pad_txt_files
except Exception:
    sys.path.insert(0, str(code_directory))
    from hci_stimuli import StimuliGenerator, pad_txt_files


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
    ADD_WIDTH = math.ceil(math.log2(TOT_MEM_SIZE * 1000))
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
    n_words = (TOT_MEM_SIZE * 1000 / N_BANKS) / (DATA_WIDTH / 8)
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
    LIST_OF_FORBIDDEN_ADDRESSES_WRITE = []
    LIST_OF_FORBIDDEN_ADDRESSES_READ = []

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
        allowed = {"random", "linear", "2d", "3d", "idle", "matmul_phased"}
        aliases = {"matmul": "matmul_phased"}

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
            config in {'linear', 'matmul_phased'}
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
        # Keep forbidden-address filtering local to this pattern invocation.
        # This allows intended buffer reuse across phases (e.g. double buffering)
        # while still avoiding duplicates inside a single pattern generator call.
        forbidden_read_local = list(LIST_OF_FORBIDDEN_ADDRESSES_READ)
        forbidden_write_local = list(LIST_OF_FORBIDDEN_ADDRESSES_WRITE)

        if config == 'random':
            tpct = pattern_config.get('traffic_pct')
            next_start_id = master.random_gen(
                next_start_id,
                forbidden_read_local,
                forbidden_write_local,
                region_base=region_base,
                region_size=region_size,
                traffic_pct=int(tpct) if tpct is not None else 100,
                traffic_read_pct=pattern_config.get('traffic_read_pct'),
                append=append,
            )
        elif config == 'linear':
            tpct = pattern_config.get('traffic_pct')
            next_start_id = master.linear_gen(
                stride0, start_address, next_start_id,
                forbidden_read_local,
                forbidden_write_local,
                traffic_pct=int(tpct) if tpct is not None else 100,
                traffic_read_pct=pattern_config.get('traffic_read_pct'),
                append=append,
            )
        elif config == '2d':
            next_start_id = master.gen_2d(
                stride0, len_d0, stride1, start_address, next_start_id,
                forbidden_read_local,
                forbidden_write_local,
                idle_cycles_between_phases=int(pattern_config.get('idle_cycles_between_phases', 0)),
                append=append,
            )
        elif config == '3d':
            next_start_id = master.gen_3d(
                stride0, len_d0, stride1, len_d1, stride2, start_address, next_start_id,
                forbidden_read_local,
                forbidden_write_local,
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
                forbidden_read_local,
                forbidden_write_local,
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

    # Emit SV literals
    hex_width = max(1, (N_DRIVERS + 3) // 4)
    per_driver_literals = []
    for i in range(N_DRIVERS):
        slot_literals = [f"{N_DRIVERS}'h{fence_masks[i][f]:0{hex_width}x}" for f in range(max_fences)]
        per_driver_literals.append("'{" + ", ".join(slot_literals) + "}")
    fence_masks_param = "'{" + ", ".join(per_driver_literals) + "}"

    # FENCE_REQ_LEVELS[N_DRIVERS][MAX_FENCES][N_DRIVERS] — int unsigned
    # Pack FENCE_REQ_LEVELS as FENCE_REQ_LEVELS_PACKED[i][f] = N_DRIVERS*4-bit vector.
    # Bits [j*4+3:j*4] = required fence_idx[j] (4 bits, supports 0..15).
    LEVEL_BITS = 4
    packed_width = N_DRIVERS * LEVEL_BITS
    packed_hex_digits = (packed_width + 3) // 4
    req_driver_literals = []
    for i in range(N_DRIVERS):
        fence_literals = []
        for f in range(max_fences):
            val = 0
            for j in range(N_DRIVERS):
                val |= (req_levels[i][f][j] & 0xF) << (j * LEVEL_BITS)
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
            f"# FENCE_REQ_LEVELS_PACKED[i][f]: packed {N_DRIVERS*4}-bit vector, bits [j*4+3:j*4] = min fence_idx[j].\n"
            f"MAX_FENCES_PARAM := {max_fences}\n"
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

    def _estimate_pattern_cycles(pattern_config, mem_access_type, n_test):
        # Intentionally simple temporal model:
        # - one time unit per transaction, plus optional req=0 idles from traffic shaping
        # - no interconnect stall/conflict modeling
        # - explicit start_delay_cycles is still honored separately
        base = max(0, int(n_test))
        tpct = pattern_config.get('traffic_pct')
        n_idles_per_req = 0
        if tpct is not None:
            tp = max(1, min(100, int(tpct)))
            n_idles_per_req = 0 if tp >= 100 else int(round((100 - tp) / tp))
        cycles = base * (1 + n_idles_per_req)
        # Keep explicit matmul phase-boundary idle modeling.
        if mem_access_type == 'matmul_phased':
            idle_between = int(pattern_config.get('idle_cycles_between_phases', 0))
            if idle_between > 0:
                ra = max(0, int(pattern_config.get('matmul_ratio_a', 1)))
                rb = max(0, int(pattern_config.get('matmul_ratio_b', 1)))
                rc = max(0, int(pattern_config.get('matmul_ratio_c', 1)))
                if ra == 0 and rb == 0 and rc == 0:
                    ra, rb, rc = 1, 1, 1
                s = ra + rb + rc
                ca = (base * ra) // s
                cb = (base * rb) // s
                cc = base - ca - cb
                phase_gaps = 0
                if ca > 0 and (cb > 0 or cc > 0):
                    phase_gaps += 1
                if cb > 0 and cc > 0:
                    phase_gaps += 1
                cycles += idle_between * phase_gaps
        return int(cycles)

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
                'cycles': int(_estimate_pattern_cycles(pat, mem_access_type, n_test)),
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
    word_bytes = DATA_WIDTH // 8
    bank_stride_bytes = N_BANKS * word_bytes
    lines = []
    lines.append("=" * 72)
    lines.append("MEMORY MAP REPORT")
    lines.append(f"  Total memory : {TOT_MEM_SIZE} KiB  ({TOT_MEM_SIZE * 1024} B)")
    lines.append(f"  Banks        : {N_BANKS}  x  {word_bytes} B/word  (interleaved, stride {bank_stride_bytes} B)")
    lines.append(f"  Data width   : {DATA_WIDTH} b LOG  /  {HWPE_WIDTH_FACT * DATA_WIDTH} b HWPE")
    lines.append(
        f"  Drivers({DW_NARROW} bit) : "
        f"CORE={N_CORE_CFG}, DMA={N_DMA_CFG}, EXT={N_EXT_CFG}  (LOG total={N_LOG_CFG})"
    )
    lines.append(
        f"  Drivers({DW_WIDE} bit) : "
        f"HWPE={N_HWPE_CFG}"
    )
    lines.append(
        f"  Interconnect type : {INTERCO_TYPE}  |  "
        f"Narrow master ports ({DW_NARROW} bit)={N_NARROW_HCI_CFG}  |  "
        f"Wide master ports ({DW_WIDE} bit)={N_WIDE_HCI_CFG}  |  "
        f"Slave ports (banks)={N_BANKS}"
    )
    lines.append("=" * 72)
    for entry in memory_map_entries:
        lines.append(f"\n  [{entry['label']}]  pattern={entry['pattern']}  n_transactions={entry['n']}")
        if 'info' in entry:
            lines.append(f"    {entry['info']}")
        for k, v in entry.get('detail', {}).items():
            lines.append(f"    {k:<14}: {v}")
    lines.append("")
    lines.append("  Job / dependency map:")
    for job, drivers in sorted(job_to_drivers.items()):
        driver_names = [_driver_name(d) for d in drivers]
        lines.append(f"    job '{job}': {', '.join(driver_names)}")
    for i in range(N_DRIVERS):
        name = _driver_name(i)
        for f, mask in enumerate(fence_masks[i]):
            if mask:
                deps = [_driver_name(j) for j in range(N_DRIVERS) if mask & (1 << j)]
                lines.append(f"    {name} after pattern[{f}] (fence {f}) waits for: {', '.join(deps)}")
    lines.append("")
    lines.append("  Temporal schedule (transaction-count model):")
    lines.append(f"    Total modeled time: {total_cycles} units (1 unit = 1 transaction)")
    lines.append("    Note: Declared wait_for_jobs dependencies are used for scheduling.")
    lines.append("    Note: Per-driver list order is also enforced (pattern p[i] -> p[i+1]).")
    lines.append("    Note: No interconnect contention/stall timing is modeled.")
    if mux_serialization_applied:
        lines.append("    Note: MUX mode serializes HWPE execution by job order, then HWPE ID (tb_hci-like).")
        lines.append(f"    MUX job order: {', '.join(mux_phase_order)}")
    if schedule_has_cycle:
        lines.append("    WARNING: dependency cycle detected while scheduling; using fallback order.")
    for d in range(N_DRIVERS):
        if d not in driver_windows:
            continue
        w = driver_windows[d]
        lines.append(f"    {w['name']:<8}: [{w['start']:>6}, {w['end']:>6})  dur={w['end'] - w['start']:>6}")
        for node in [n for n in pattern_nodes if n['driver_idx'] == d]:
            reg_tokens = []
            for reg in node['regions']:
                reg_tokens.append(f"{reg['label']}@0x{reg['base']:08x}+{reg['size']}B")
            reg_text = ", ".join(reg_tokens) if reg_tokens else "no regions"
            lines.append(
                f"      p{node['pattern_idx']} job={node['job']} "
                f"[{node['start_cycle']},{node['end_cycle']}) "
                f"type={node['mem_access_type']} n={node['n_transactions']}  {reg_text}"
            )
    lines.append("")
    lines.append("  Memory region lifetimes:")
    for key in sorted(regions_timeline.keys(), key=lambda k: (k[0], k[1], k[2])):
        reg = regions_timeline[key]
        users = sorted({a['driver_name'] for a in reg['accesses']})
        lines.append(
            f"    {reg['label']:<8} 0x{reg['base']:08x}-0x{reg['end']:08x} "
            f"({reg['size']:>6} B)  lifetime=[{reg['lifetime_start']},{reg['lifetime_end']})  "
            f"users={', '.join(users)}"
        )
    lines.append("=" * 72)

    report_text = "\n".join(lines) + "\n"
    print("\n" + report_text)
    memory_map_path = generated_dir / 'memory_map.txt'
    memory_map_path.write_text(report_text, encoding='utf-8')
    print(f"Memory map written: {memory_map_path}")

    # -----------------------------------------------------------------------
    # Build memory_lifetime.html (simple SVG timeline view)
    # -----------------------------------------------------------------------
    palette = [
        "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#17becf",
        "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#9467bd",
        "#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e",
        "#e6ab02", "#a6761d", "#666666",
    ]

    def _color_for_driver(drv_idx):
        return palette[drv_idx % len(palette)]

    def _tick_step(total):
        if total <= 10:
            return 1
        raw = max(1, total // 10)
        mag = 10 ** int(math.log10(raw))
        return int(math.ceil(raw / mag) * mag)

    total_for_plot = max(1, total_cycles)
    chart_width = 1280
    x_left = 220
    x_right = 24
    plot_w = chart_width - x_left - x_right
    row_h = 80
    y_top = 36
    exec_rows = [driver_windows[d] for d in sorted(driver_windows.keys())]
    exec_h = y_top + row_h * len(exec_rows) + 72
    tick = _tick_step(total_for_plot)
    ticks = list(range(0, total_for_plot + 1, tick))
    if ticks[-1] != total_for_plot:
        ticks.append(total_for_plot)

    exec_svg = []
    exec_svg.append(f'<svg width="{chart_width}" height="{exec_h}" viewBox="0 0 {chart_width} {exec_h}" xmlns="http://www.w3.org/2000/svg">')
    exec_svg.append('<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    exec_svg.append(f'<text x="{x_left}" y="20" font-family="Arial, sans-serif" font-size="14" font-weight="700">Execution Timeline (transaction-count model)</text>')
    for t in ticks:
        x = x_left + (t / total_for_plot) * plot_w
        exec_svg.append(f'<line x1="{x:.2f}" y1="{y_top - 6}" x2="{x:.2f}" y2="{exec_h - 52}" stroke="#e0e0e0" stroke-width="1"/>')
        exec_svg.append(f'<text x="{x:.2f}" y="{exec_h - 36}" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#555">{t}</text>')
    exec_svg.append(
        f'<text x="{x_left + (plot_w / 2):.2f}" y="{exec_h - 18}" text-anchor="middle" '
        'font-family="Arial, sans-serif" font-size="12" fill="#333">Transaction number</text>'
    )
    exec_svg.append(
        f'<text x="{x_left + (plot_w / 2):.2f}" y="{exec_h - 2}" text-anchor="middle" '
        'font-family="Arial, sans-serif" font-size="11" fill="#555">'
        'Issued memory transactions (r/w) and computation cycles (i.e., req = 0) are both modeled here.'
        '</text>'
    )

    def _rw_mix_text(node):
        rpct = node.get('traffic_read_pct')
        if rpct is None:
            read_bytes = 0
            write_bytes = 0
            for reg in node.get('regions', []):
                label_l = str(reg.get('label', '')).lower()
                size_b = max(0, int(reg.get('size', 0)))
                if 'read' in label_l and 'write' not in label_l:
                    read_bytes += size_b
                elif 'write' in label_l and 'read' not in label_l:
                    write_bytes += size_b
            if (read_bytes + write_bytes) > 0:
                rpct = int(round(100.0 * read_bytes / (read_bytes + write_bytes)))
            else:
                rpct = 50
        rpct = max(0, min(100, int(rpct)))
        if rpct == 0:
            return "100% writes"
        if rpct == 100:
            return "100% reads"
        return f"{rpct}% reads / {100 - rpct}% writes"

    def _fmt_kib(bytes_v):
        return f"{(max(0, int(bytes_v)) / 1024.0):.1f} KiB"

    def _outside_detail_lines(node, base_addr, size_kib):
        regs = list(node.get('regions', []))
        label_map = {str(r.get('label', '')): r for r in regs}
        has_matmul_regs = any(k in label_map for k in ('A(read)', 'B(read)', 'C(write)'))
        is_matmul = node.get('mem_access_type') in {'matmul', 'matmul_phased'} or has_matmul_regs

        if is_matmul:
            mat_lines = []
            for lbl, short in [('A(read)', 'A'), ('B(read)', 'B'), ('C(write)', 'C')]:
                if lbl in label_map:
                    r = label_map[lbl]
                    mat_lines.append(f"{short}@0x{int(r['base']):08x} ({_fmt_kib(r['size'])})")
            if not mat_lines:
                return [f"@0x{base_addr:08x}", f"{size_kib:.1f} KiB"]
            return mat_lines

        if regs:
            r0 = regs[0]
            return [f"@0x{int(r0['base']):08x}", f"{_fmt_kib(r0['size'])}"]
        return [f"@0x{base_addr:08x}", f"{size_kib:.1f} KiB"]

    for row_idx, row in enumerate(exec_rows):
        y = y_top + row_idx * row_h
        name = html.escape(row['name'])
        label_color = "#111111" if row['is_hwpe'] else "#555555"
        exec_svg.append(f'<text x="{x_left - 10}" y="{y + 34}" text-anchor="end" font-family="Arial, sans-serif" font-size="12" fill="{label_color}">{name}</text>')
        exec_svg.append(f'<line x1="{x_left}" y1="{y + row_h - 1}" x2="{x_left + plot_w}" y2="{y + row_h - 1}" stroke="#f0f0f0" stroke-width="1"/>')
        nodes = [n for n in pattern_nodes if n['driver_idx'] == row['driver_idx']]
        for node in nodes:
            if node['end_cycle'] <= node['start_cycle']:
                continue
            x = x_left + (node['start_cycle'] / total_for_plot) * plot_w
            w = max(1.0, ((node['end_cycle'] - node['start_cycle']) / total_for_plot) * plot_w)
            color = _color_for_driver(node['driver_idx'])
            base_addr = min((int(r.get('base', 0)) for r in node.get('regions', [])), default=0)
            size_kib = (int(node['n_transactions']) * int(node.get('txn_bytes', 1))) / 1024.0
            rw_mix = _rw_mix_text(node)
            line1_full = f"{node['job']}"
            line2_full = f"{node['mem_access_type']}"
            line3_full = rw_mix
            outside_lines = _outside_detail_lines(node, base_addr, size_kib)
            title = (
                f"{node['driver_name']} p{node['pattern_idx']} job={node['job']} "
                f"[{node['start_cycle']}, {node['end_cycle']}) "
                f"{node['mem_access_type']} n={node['n_transactions']} "
                f"base=0x{base_addr:08x} {size_kib:.1f}KiB {rw_mix} "
                f"{' | '.join(outside_lines)}"
            )
            exec_svg.append('<g style="cursor:help;">')
            exec_svg.append(f'<title>{html.escape(title)}</title>')
            exec_svg.append(
                f'<rect x="{x:.2f}" y="{y + 4}" width="{w:.2f}" height="34" '
                f'rx="3" ry="3" fill="{color}" fill-opacity="0.82" stroke="#222" stroke-width="0.2"/>'
            )
            line1 = html.escape(line1_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 15}" font-family="Arial, sans-serif" font-size="9" '
                f'fill="#ffffff" style="pointer-events:none;">{line1}</text>'
            )
            line2 = html.escape(line2_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 25}" font-family="Arial, sans-serif" font-size="8" '
                f'fill="#ffffff" style="pointer-events:none;">{line2}</text>'
            )
            line3 = html.escape(line3_full)
            exec_svg.append(
                f'<text x="{x + 4:.2f}" y="{y + 34}" font-family="Arial, sans-serif" font-size="8" '
                f'fill="#ffffff" style="pointer-events:none;">{line3}</text>'
            )
            for ext_idx, ext in enumerate(outside_lines):
                y_ext = y + 49 + (ext_idx * 9)
                ext_txt = html.escape(ext)
                exec_svg.append(
                    f'<text x="{x + 2:.2f}" y="{y_ext:.2f}" font-family="Arial, sans-serif" font-size="8" '
                    f'fill="#333333" style="pointer-events:none;">{ext_txt}</text>'
                )
            exec_svg.append('</g>')
    exec_svg.append('</svg>')

    region_rows = [regions_timeline[k] for k in sorted(regions_timeline.keys(), key=lambda k: (k[0], k[1], k[2]))]
    overlap_rows = []
    overlaps_by_region = {i: [] for i in range(len(region_rows))}
    for i in range(len(region_rows)):
        a = region_rows[i]
        for j in range(i + 1, len(region_rows)):
            b = region_rows[j]
            ov_base = max(a['base'], b['base'])
            ov_end = min(a['end'], b['end'])
            if ov_base <= ov_end:
                ov_size = ov_end - ov_base + 1
                overlap_rows.append({
                    'a_idx': i,
                    'b_idx': j,
                    'ov_base': ov_base,
                    'ov_end': ov_end,
                    'ov_size': ov_size,
                })
                overlaps_by_region[i].append((j, ov_base, ov_end, ov_size))
                overlaps_by_region[j].append((i, ov_base, ov_end, ov_size))

    used_min = min((reg['base'] for reg in region_rows), default=0)
    used_max = max((reg['end'] for reg in region_rows), default=0)
    if used_max < used_min:
        used_max = used_min
    used_span = max(1, used_max - used_min + 1)

    map_left = 170
    map_right = 24
    map_plot_w = chart_width - map_left - map_right
    map_h = 124
    bar_y = 56
    bar_h = 24
    region_map_svg = []
    region_map_svg.append(f'<svg width="{chart_width}" height="{map_h}" viewBox="0 0 {chart_width} {map_h}" xmlns="http://www.w3.org/2000/svg">')
    region_map_svg.append('<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>')
    region_map_svg.append(
        f'<text x="{map_left}" y="20" font-family="Arial, sans-serif" font-size="14" font-weight="700">'
        f"Memory Region Blocks (used range 0x{used_min:08x} - 0x{used_max:08x})"
        f"</text>"
    )
    region_map_svg.append(
        f'<rect x="{map_left}" y="{bar_y}" width="{map_plot_w}" height="{bar_h}" '
        f'fill="#f6f6f6" stroke="#cfcfcf" stroke-width="1"/>'
    )
    for pct in [0, 25, 50, 75, 100]:
        x = map_left + (pct / 100.0) * map_plot_w
        addr = used_min + int(((used_span - 1) * pct) / 100.0)
        region_map_svg.append(f'<line x1="{x:.2f}" y1="{bar_y - 8}" x2="{x:.2f}" y2="{bar_y + bar_h + 8}" stroke="#d7d7d7" stroke-width="1"/>')
        region_map_svg.append(
            f'<text x="{x:.2f}" y="{bar_y + bar_h + 22}" text-anchor="middle" '
            f'font-family="Arial, sans-serif" font-size="11" fill="#555">0x{addr:08x}</text>'
        )
    for reg in region_rows:
        x = map_left + ((reg['base'] - used_min) / used_span) * map_plot_w
        w = max(1.0, (reg['size'] / used_span) * map_plot_w)
        color = _color_for_driver(reg['accesses'][0]['driver_idx']) if reg['accesses'] else "#888888"
        title = (
            f"{reg['label']} 0x{reg['base']:08x}-0x{reg['end']:08x} "
            f"size={reg['size']}B accesses={len(reg['accesses'])}"
        )
        region_map_svg.append(
            f'<rect x="{x:.2f}" y="{bar_y + 2}" width="{w:.2f}" height="{bar_h - 4}" '
            f'rx="2" ry="2" fill="{color}" fill-opacity="0.62" stroke="#222" stroke-width="0.35">'
            f'<title>{html.escape(title)}</title></rect>'
        )
        if w >= 92:
            region_map_svg.append(
                f'<text x="{x + 4:.2f}" y="{bar_y + 16}" font-family="Arial, sans-serif" '
                f'font-size="10" fill="#111">{html.escape(reg["label"])}</text>'
            )
    region_map_svg.append('</svg>')

    legend_items = []
    for d in sorted(driver_windows.keys()):
        n = _driver_name(d)
        c = _color_for_driver(d)
        legend_items.append(
            f'<span style="display:inline-flex;align-items:center;margin-right:12px;margin-bottom:6px;">'
            f'<span style="display:inline-block;width:11px;height:11px;background:{c};margin-right:5px;border:1px solid #222;"></span>'
            f'<span>{html.escape(n)}</span></span>'
        )

    region_cards = []
    for idx, reg in enumerate(region_rows):
        access_rows = []
        accesses = sorted(reg['accesses'], key=lambda a: (a['driver_idx'], a['pattern_idx'], a['start']))
        for acc in accesses:
            desc = acc['description'] if acc['description'] else "-"
            access_rows.append(
                "<tr>"
                f"<td>{html.escape(acc['driver_name'])}</td>"
                f"<td>p{acc['pattern_idx']}</td>"
                f"<td>{html.escape(acc['job'])}</td>"
                f"<td>{html.escape(desc)}</td>"
                f"<td>[{acc['start']}, {acc['end']})</td>"
                "</tr>"
            )
        overlap_refs = overlaps_by_region.get(idx, [])
        if overlap_refs:
            ov_txt = ", ".join(
                [
                    f"{html.escape(region_rows[j]['label'])} "
                    f"(0x{ovb:08x}-0x{ove:08x}, {ovs} B)"
                    for (j, ovb, ove, ovs) in overlap_refs
                ]
            )
        else:
            ov_txt = "none"
        region_cards.append(
            "<div class='region-card'>"
            f"<div><b>{html.escape(reg['label'])}</b> | base=0x{reg['base']:08x} | end=0x{reg['end']:08x} | size={reg['size']} B</div>"
            f"<div class='meta' style='margin:4px 0 8px 0;'><b>Overlaps:</b> {ov_txt}</div>"
            "<table class='smalltbl'><thead><tr>"
            "<th>Driver/HWPE</th><th>Pattern</th><th>Job</th><th>Description</th><th>Modeled interval</th>"
            "</tr></thead><tbody>"
            f"{''.join(access_rows)}"
            "</tbody></table>"
            "</div>"
        )

    overlap_table_rows = []
    for ov in overlap_rows:
        a = region_rows[ov['a_idx']]
        b = region_rows[ov['b_idx']]
        overlap_table_rows.append(
            "<tr>"
            f"<td>{html.escape(a['label'])} (0x{a['base']:08x}-0x{a['end']:08x})</td>"
            f"<td>{html.escape(b['label'])} (0x{b['base']:08x}-0x{b['end']:08x})</td>"
            f"<td>0x{ov['ov_base']:08x}</td>"
            f"<td>0x{ov['ov_end']:08x}</td>"
            f"<td>{ov['ov_size']}</td>"
            "</tr>"
        )

    note = "Timeline follows declared wait_for_jobs dependencies from workload.json."
    note_2 = (
        "Time axis is transaction-count based only "
        "(no interconnect conflict/stall/arbitration modeling)."
    )
    note_2b = "Per-driver list order is still enforced by stimulus/fence sequencing."
    note_3 = ""
    if mux_serialization_applied:
        note_3 = (
            "MUX mode: HWPE execution is serialized by job order, "
            "with lower HWPE ID first inside each job (tb_hci-like)."
        )
        if mux_phase_order:
            note_3 += f" Job order: {', '.join(mux_phase_order)}."
    note_3_html = f"<div class='meta'>{html.escape(note_3)}</div>" if note_3 else ""
    cycle_warning_html = (
        "<p style='margin:8px 0;color:#b00020;font-weight:600;'>Warning: dependency cycle detected; fallback scheduling order used.</p>"
        if schedule_has_cycle else ""
    )
    overlap_html = (
        "<table><thead><tr><th>Region A</th><th>Region B</th><th>Overlap Base</th><th>Overlap End</th><th>Overlap Size (B)</th></tr></thead><tbody>"
        f"{''.join(overlap_table_rows)}"
        "</tbody></table>"
        if overlap_table_rows else
        "<div class='meta'>No overlaps detected among used regions.</div>"
    )

    html_doc = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>Memory Access Region View (Transaction-Count Model)</title>"
        "<style>"
        "body{font-family:Arial,sans-serif;margin:18px;background:#fafafa;color:#111;}"
        "h1{font-size:20px;margin:0 0 6px 0;}h2{font-size:16px;margin:18px 0 8px 0;}"
        ".meta{font-size:13px;color:#333;margin-bottom:10px;}"
        ".panel{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:14px;overflow-x:auto;}"
        "table{border-collapse:collapse;width:100%;font-size:12px;background:#fff;}"
        "th,td{border:1px solid #ddd;padding:5px 7px;text-align:left;vertical-align:top;}"
        "th{background:#f3f3f3;}"
        ".region-card{border:1px solid #dcdcdc;border-radius:6px;padding:10px;margin-bottom:10px;background:#fff;}"
        ".smalltbl{border-collapse:collapse;width:100%;font-size:11px;background:#fff;}"
        ".smalltbl th,.smalltbl td{border:1px solid #ddd;padding:4px 6px;text-align:left;vertical-align:top;}"
        ".smalltbl th{background:#f7f7f7;}"
        "</style></head><body>"
        "<h1>Memory Access Region View</h1>"
        f"<div class='meta'><b>Drivers ({DW_NARROW} bit):</b> "
        f"CORE={N_CORE_CFG}, DMA={N_DMA_CFG}, EXT={N_EXT_CFG}</div>"
        f"<div class='meta'><b>Drivers ({DW_WIDE} bit):</b> HWPE={N_HWPE_CFG}</div>"
        f"<div class='meta'><b>Interconnect type:</b> {html.escape(INTERCO_TYPE)} | "
        f"<b>Narrow master ports ({DW_NARROW} bit):</b> {N_NARROW_HCI_CFG} | "
        f"<b>Wide master ports ({DW_WIDE} bit):</b> {N_WIDE_HCI_CFG} | "
        f"<b>Slave ports (banks):</b> {N_BANKS} | "
        f"<b>Total modeled time:</b> {total_cycles} units</div>"
        f"<div class='meta'>{html.escape(note)}</div>"
        f"<div class='meta'>{html.escape(note_2)}</div>"
        f"<div class='meta'>{html.escape(note_2b)}</div>"
        f"{note_3_html}"
        f"{cycle_warning_html}"
        "<div class='panel'><h2 style='margin-top:0;'>Legend</h2>"
        f"{''.join(legend_items)}</div>"
        "<div class='panel'>"
        f"{''.join(exec_svg)}"
        "</div>"
        "<div class='panel'>"
        f"{''.join(region_map_svg)}"
        "</div>"
        "<h2>Region Usage Blocks</h2>"
        f"{''.join(region_cards)}"
        "<h2>Overlapping Regions</h2>"
        f"{overlap_html}"
        "</body></html>"
    )

    memory_lifetime_path = generated_dir / 'memory_lifetime.html'
    memory_lifetime_path.write_text(html_doc, encoding='utf-8')
    print(f"Memory lifetime plot written: {memory_lifetime_path}")

    # -----------------------------------------------------------------------
    # Apply per-master start delays
    # -----------------------------------------------------------------------
    for fpath, delay, dw in pending_start_delays:
        if fpath.exists():
            idle_line = "0 " + "0" * IW + " 0 " + "0" * dw + " " + "0" * ADD_WIDTH + "\n"
            original = fpath.read_text(encoding='ascii')
            fpath.write_text(idle_line * delay + original, encoding='ascii')

    # -----------------------------------------------------------------------
    # Pad all stimuli files to equal length
    # -----------------------------------------------------------------------
    pad_txt_files(str(stimuli_dir), IW, DATA_WIDTH, ADD_WIDTH, HWPE_WIDTH_FACT)
    print("STEP 1 COMPLETED: pad stimuli files")

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
