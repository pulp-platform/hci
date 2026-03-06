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

    log_masters = workload_config['log_masters']
    hwpe_masters = workload_config['hwpe_masters']

    # Derived parameters
    ADD_WIDTH = math.ceil(math.log2(TOT_MEM_SIZE * 1000))
    N_LOG = N_CORE + N_DMA + N_EXT
    IW = 8

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
        label = f"{kind}_{local_idx}" + (f" ({description})" if description else "")
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
        if mem_access_type == 'linear':
            length = master_config.get('length')
            if length is not None:
                return int(length)
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

    def _generate_master(
        filepath: Path,
        master_config: dict,
        *,
        is_hwpe: bool,
        master_global_idx: int,
        master_local_idx: int,
        n_peers_of_kind: int,
    ):
        nonlocal next_start_id
        data_width = HWPE_WIDTH_FACT * DATA_WIDTH if is_hwpe else DATA_WIDTH
        kind = 'master_hwpe' if is_hwpe else 'master_log'

        master = StimuliGenerator(
            IW, DATA_WIDTH, N_BANKS, TOT_MEM_SIZE, data_width, ADD_WIDTH,
            str(filepath), 0, master_global_idx
        )

        if 'mem_access_type' not in master_config:
            print(f"ERROR: {kind}_{master_local_idx} is missing mem_access_type.")
            sys.exit(1)

        config = _normalize_mem_access_type(
            master_config['mem_access_type'],
            f"{kind}_{master_local_idx}",
        )
        start_address = str(master_config.get('start_address', '0'))
        stride0 = int(master_config.get('stride0', 0))
        len_d0 = int(master_config.get('len_d0', 0))
        stride1 = int(master_config.get('stride1', 0))
        len_d1 = int(master_config.get('len_d1', 0))
        stride2 = int(master_config.get('stride2', 0))

        # Region parameters
        total_mem_bytes = int(TOT_MEM_SIZE * 1024)
        access_bytes = max(1, int(data_width // 8))
        default_region_size = total_mem_bytes // max(1, n_peers_of_kind)
        default_region_base = master_local_idx * default_region_size

        region_base = _parse_maybe_bin_int(master_config.get('region_base_address'), default_region_base)
        region_size = _parse_maybe_bin_int(master_config.get('region_size_bytes'), default_region_size)

        region_base = (region_base // access_bytes) * access_bytes
        if region_base >= total_mem_bytes:
            region_base = region_base % total_mem_bytes
        region_size = (max(0, region_size) // access_bytes) * access_bytes
        if region_size <= 0:
            region_size = (default_region_size // access_bytes) * access_bytes
        if region_base + region_size > total_mem_bytes:
            region_size = ((total_mem_bytes - region_base) // access_bytes) * access_bytes

        n_test = _resolve_n_transactions(master_config, config, data_width, kind, master_local_idx)
        master.N_TEST = n_test

        # Start delay: prepend idle lines directly to the stimuli file after generation
        start_delay = int(master_config.get('start_delay_cycles', 0))
        if start_delay > 0:
            pending_start_delays.append((filepath, start_delay, data_width))

        if config == 'random':
            tpct = master_config.get('traffic_pct')
            next_start_id = master.random_gen(
                next_start_id,
                LIST_OF_FORBIDDEN_ADDRESSES_READ,
                LIST_OF_FORBIDDEN_ADDRESSES_WRITE,
                region_base=region_base,
                region_size=region_size,
                traffic_pct=int(tpct) if tpct is not None else 100,
                traffic_read_pct=master_config.get('traffic_read_pct'),
            )
        elif config == 'linear':
            tpct = master_config.get('traffic_pct')
            next_start_id = master.linear_gen(
                stride0, start_address, next_start_id,
                LIST_OF_FORBIDDEN_ADDRESSES_READ,
                LIST_OF_FORBIDDEN_ADDRESSES_WRITE,
                traffic_pct=int(tpct) if tpct is not None else 100,
                traffic_read_pct=master_config.get('traffic_read_pct'),
            )
        elif config == '2d':
            next_start_id = master.gen_2d(
                stride0, len_d0, stride1, start_address, next_start_id,
                LIST_OF_FORBIDDEN_ADDRESSES_READ,
                LIST_OF_FORBIDDEN_ADDRESSES_WRITE,
                idle_cycles_between_phases=int(master_config.get('idle_cycles_between_phases', 0)),
            )
        elif config == '3d':
            next_start_id = master.gen_3d(
                stride0, len_d0, stride1, len_d1, stride2, start_address, next_start_id,
                LIST_OF_FORBIDDEN_ADDRESSES_READ,
                LIST_OF_FORBIDDEN_ADDRESSES_WRITE,
                idle_cycles_between_phases=int(master_config.get('idle_cycles_between_phases', 0)),
            )
        elif config == 'idle':
            next_start_id = master.idle_gen(next_start_id)
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
                LIST_OF_FORBIDDEN_ADDRESSES_READ,
                LIST_OF_FORBIDDEN_ADDRESSES_WRITE,
                region_base,
                region_size,
                int(master_config.get('matmul_ratio_a', 1)),
                int(master_config.get('matmul_ratio_b', 1)),
                int(master_config.get('matmul_ratio_c', 1)),
                idle_cycles_between_phases=int(master_config.get('idle_cycles_between_phases', 0)),
                region_base_address_a=_parse_maybe_bin_int(master_config.get('region_base_address_a'), None),
                region_size_bytes_a=_parse_maybe_bin_int(master_config.get('region_size_bytes_a'), None),
                region_base_address_b=_parse_maybe_bin_int(master_config.get('region_base_address_b'), None),
                region_size_bytes_b=_parse_maybe_bin_int(master_config.get('region_size_bytes_b'), None),
                region_base_address_c=_parse_maybe_bin_int(master_config.get('region_base_address_c'), None),
                region_size_bytes_c=_parse_maybe_bin_int(master_config.get('region_size_bytes_c'), None),
            )

        _record_memory_map(
            kind, master_local_idx,
            master_config.get('description', ''),
            config, n_test, data_width, access_bytes,
            region_base, region_size,
            start_address, stride0, len_d0, stride1, len_d1, stride2,
            master_config, total_mem_bytes,
        )

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
    # Compute WAIT_MASKS and emit phases.mk
    # -----------------------------------------------------------------------
    N_DRIVERS = N_LOG + N_HWPE

    phase_to_drivers: dict[str, list[int]] = {}
    driver_phases: list[str] = []

    for i, m in enumerate(log_masters):
        phase = str(m.get('phase', 'default'))
        driver_phases.append(phase)
        phase_to_drivers.setdefault(phase, []).append(i)

    for i, m in enumerate(hwpe_masters):
        gidx = N_LOG + i
        phase = str(m.get('phase', 'default'))
        driver_phases.append(phase)
        phase_to_drivers.setdefault(phase, []).append(gidx)

    wait_masks: list[int] = [0] * N_DRIVERS

    for i, m in enumerate(log_masters):
        mask = 0
        for dep_phase in m.get('wait_for', []):
            for dep_drv in phase_to_drivers.get(str(dep_phase), []):
                mask |= (1 << dep_drv)
        wait_masks[i] = mask

    for i, m in enumerate(hwpe_masters):
        gidx = N_LOG + i
        mask = 0
        for dep_phase in m.get('wait_for', []):
            for dep_drv in phase_to_drivers.get(str(dep_phase), []):
                mask |= (1 << dep_drv)
        wait_masks[gidx] = mask

    hex_width = max(1, (N_DRIVERS + 3) // 4)
    mask_literals = [f"{N_DRIVERS}'h{wait_masks[i]:0{hex_width}x}" for i in range(N_DRIVERS)]
    wait_masks_param = "'{" + ", ".join(mask_literals) + "}"

    if args.emit_phases_mk:
        phases_mk_path = Path(args.emit_phases_mk)
        phases_mk_path.parent.mkdir(parents=True, exist_ok=True)
        phases_mk_path.write_text(
            "# Auto-generated by main.py - DO NOT EDIT MANUALLY\n"
            "# Per-driver dependency masks for tb_hci.sv (WAIT_MASKS_PARAM).\n"
            f"# Drivers 0..{N_LOG-1} = log masters, {N_LOG}..{N_DRIVERS-1} = HWPE masters.\n"
            f"WAIT_MASKS_PARAM := {wait_masks_param}\n",
            encoding='utf-8',
        )
        print(f"PHASES.MK written: {phases_mk_path}")

    # -----------------------------------------------------------------------
    # Build and emit memory map report
    # -----------------------------------------------------------------------
    word_bytes = DATA_WIDTH // 8
    bank_stride_bytes = N_BANKS * word_bytes
    lines = []
    lines.append("=" * 72)
    lines.append("MEMORY MAP REPORT")
    lines.append(f"  Total memory : {TOT_MEM_SIZE} KiB  ({TOT_MEM_SIZE * 1024} B)")
    lines.append(f"  Banks        : {N_BANKS}  x  {word_bytes} B/word  (interleaved, stride {bank_stride_bytes} B)")
    lines.append(f"  Data width   : {DATA_WIDTH} b LOG  /  {HWPE_WIDTH_FACT * DATA_WIDTH} b HWPE")
    lines.append("=" * 72)
    for entry in memory_map_entries:
        lines.append(f"\n  [{entry['label']}]  pattern={entry['pattern']}  n_transactions={entry['n']}")
        if 'info' in entry:
            lines.append(f"    {entry['info']}")
        for k, v in entry.get('detail', {}).items():
            lines.append(f"    {k:<14}: {v}")
    lines.append("")
    lines.append("  Phase / dependency map:")
    for phase, drivers in sorted(phase_to_drivers.items()):
        driver_names = [f"log_{d}" if d < N_LOG else f"hwpe_{d - N_LOG}" for d in drivers]
        lines.append(f"    phase '{phase}': {', '.join(driver_names)}")
    for i in range(N_DRIVERS):
        if wait_masks[i]:
            name = f"log_{i}" if i < N_LOG else f"hwpe_{i - N_LOG}"
            deps = [f"log_{j}" if j < N_LOG else f"hwpe_{j - N_LOG}"
                    for j in range(N_DRIVERS) if wait_masks[i] & (1 << j)]
            lines.append(f"    {name} waits for: {', '.join(deps)}")
    lines.append("=" * 72)

    report_text = "\n".join(lines) + "\n"
    print("\n" + report_text)
    memory_map_path = generated_dir / 'memory_map.txt'
    memory_map_path.write_text(report_text, encoding='utf-8')
    print(f"Memory map written: {memory_map_path}")

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
