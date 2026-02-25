"""Stimuli generator (reads JSON configs in `verif/config`).

This script is invoked by the top-level Makefile and expects three
JSON config files: workload, testbench and hardware. It produces raw
and processed stimuli in `verif/simvectors/generated`.
"""

### LIBRARIES AND DEPENDENCIES ###
import json
import sys
from pathlib import Path
import argparse
import numpy as np

code_directory = Path(__file__).resolve().parent


# Try to import the local package `hci_stimuli`. If the running
# environment doesn't include the `simvectors` directory on `sys.path`
# (for example when invoked from a different working directory), add
# `code_directory` to `sys.path` as a minimal fallback.
try:
    from hci_stimuli import StimuliGenerator, unfold_raw_txt, pad_txt_files
except Exception:
    sys.path.insert(0, str(code_directory))
    from hci_stimuli import StimuliGenerator, unfold_raw_txt, pad_txt_files


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Generate stimuli from JSON configs.")
    parser.add_argument('--workload_config', required=True, help="Path to JSON workload configuration file")
    parser.add_argument('--testbench_config', required=True, help="Path to JSON testbench configuration file")
    parser.add_argument('--hardware_config', required=True, help="Path to JSON hardware configuration file")
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
    # parse CLI args
    args = parse_args(argv)

    # load configs
    hardware_config = load_config(args.hardware_config, "Hardware configuration")
    testbench_config = load_config(args.testbench_config, "Testbench configuration")
    workload_config = load_config(args.workload_config, "Workload configuration")

    # helpers imported at module-level (with a small sys.path fallback)

    # Extract hardware parameters
    hw_params = hardware_config['parameters']
    N_BANKS = hw_params['N_BANKS']
    TOT_MEM_SIZE = hw_params['TOT_MEM_SIZE']
    DATA_WIDTH = hw_params['DATA_WIDTH']
    N_CORE = hw_params['N_CORE']
    N_DMA = hw_params['N_DMA']
    N_EXT = hw_params['N_EXT']
    N_HWPE = hw_params['N_HWPE']
    HWPE_WIDTH = hw_params['HWPE_WIDTH']

    # Extract testbench parameters
    tb_params = testbench_config['parameters']
    TEST_RATIO = tb_params['TRANSACTION_RATIO']
    N_TEST_LOG = tb_params['N_TRANSACTION_LOG']

    # Extract workload simulation parameters
    workload_sim_params = workload_config['simulation_parameters']
    CYCLE_OFFSET_LOG = workload_sim_params['CYCLE_OFFSET_LOG']
    CYCLE_OFFSET_HWPE = workload_sim_params['CYCLE_OFFSET_HWPE']
    EXACT_OR_MAX_OFFSET = workload_sim_params['EXACT_OR_MAX_OFFSET']

    # Extract workload master parameters
    log_masters = workload_config['log_masters']
    hwpe_masters = workload_config['hwpe_masters']

    # Derived parameters
    WIDTH_OF_MEMORY = DATA_WIDTH
    WIDTH_OF_MEMORY_BYTE = WIDTH_OF_MEMORY / 8
    N_WORDS = (TOT_MEM_SIZE * 1000 / N_BANKS) / WIDTH_OF_MEMORY_BYTE
    ADD_WIDTH = int(np.ceil(np.log2(TOT_MEM_SIZE * 1000)))
    N_TEST_HWPE = int(N_TEST_LOG * TEST_RATIO)
    N_LOG = N_CORE + N_DMA + N_EXT
    N_MASTER = N_LOG + N_HWPE
    IW = int(np.ceil(np.log2(N_TEST_LOG * N_LOG + N_TEST_HWPE * N_HWPE)))
    CORE_ZERO_FLAG = False
    EXT_ZERO_FLAG = False
    DMA_ZERO_FLAG = False
    HWPE_ZERO_FLAG = False

    # Validations
    if len(log_masters) != N_LOG:
        print(f"ERROR: Number of log masters in workload config ({len(log_masters)}) doesn't match hardware config N_LOG ({N_LOG})")
        sys.exit(1)

    if len(hwpe_masters) != N_HWPE:
        print(f"ERROR: Number of HWPE masters in workload config ({len(hwpe_masters)}) doesn't match hardware config N_HWPE ({N_HWPE})")
        sys.exit(1)

    if (not N_WORDS.is_integer()):
        print("ERROR: the number of words is not an integer value")
        sys.exit(1)
    if (N_MASTER < 1):
        print("ERROR: the number of masters must be > 0")
        sys.exit(1)

    # Prepare output dirs
    simvectors_dir = code_directory.resolve()
    generated_dir = (simvectors_dir / 'generated').resolve()
    raw_dir = (generated_dir / 'stimuli_raw').resolve()
    processed_dir = (generated_dir / 'stimuli_processed').resolve()
    generated_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)
    processed_dir.mkdir(parents=True, exist_ok=True)

    # Create zero files when a class of masters is absent. We keep the
    # original behaviour of creating a single 'zero' file per missing
    # class to preserve downstream expectations.
    def _create_zero_file(path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('zero', encoding='ascii')

    if N_CORE <= 0:
        CORE_ZERO_FLAG = True
        N_CORE = 1
        _create_zero_file(raw_dir / 'master_log_0.txt')
    if N_DMA <= 0:
        DMA_ZERO_FLAG = True
        N_DMA = 1
        _create_zero_file(raw_dir / f'master_log_{N_CORE}.txt')
    if N_EXT <= 0:
        EXT_ZERO_FLAG = True
        N_EXT = 1
        _create_zero_file(raw_dir / f'master_log_{N_CORE + N_DMA}.txt')
    if N_HWPE <= 0:
        HWPE_ZERO_FLAG = True
        N_HWPE = 1
        _create_zero_file(raw_dir / 'master_hwpe_0.txt')

    next_start_id = 0
    LIST_OF_FORBIDDEN_ADDRESSES_WRITE = []
    LIST_OF_FORBIDDEN_ADDRESSES_READ = []

    def _generate_master(filepath: Path, master_config: dict, *, is_hwpe: bool, master_global_idx: int):
        """Create StimuliGenerator and run the configured generation method.

        Parameters:
        - filepath: output raw txt file path
        - master_config: dict from workload.json for this master
        - is_hwpe: whether this is an HWPE master (affects data width and counts)
        - master_global_idx: global master id used by the generator
        """
        nonlocal next_start_id
        data_width = HWPE_WIDTH * DATA_WIDTH if is_hwpe else DATA_WIDTH
        n_test = N_TEST_HWPE if is_hwpe else N_TEST_LOG
        cycle_offset = CYCLE_OFFSET_HWPE if is_hwpe else CYCLE_OFFSET_LOG

        master = StimuliGenerator(
            IW, WIDTH_OF_MEMORY, N_BANKS, TOT_MEM_SIZE, data_width, ADD_WIDTH,
            str(filepath), n_test, EXACT_OR_MAX_OFFSET, cycle_offset, master_global_idx
        )

        config = str(master_config.get('mem_access_type', '0'))
        start_address = str(master_config.get('start_address', '0'))
        stride0 = int(master_config.get('stride0', 0))
        len_d0 = int(master_config.get('len_d0', 0))
        stride1 = int(master_config.get('stride1', 0))
        len_d1 = int(master_config.get('len_d1', 0))
        stride2 = int(master_config.get('stride2', 0))

        if config == '0':
            next_start_id = master.random_gen(next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        elif config == '1':
            next_start_id = master.linear_gen(stride0, start_address, next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        elif config == '2':
            next_start_id = master.gen_2d(stride0, len_d0, stride1, start_address, next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        elif config == '3':
            next_start_id = master.gen_3d(stride0, len_d0, stride1, len_d1, stride2, start_address, next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)

    def _gen_hwpe_master(master_idx, master_config, global_idx):
        nonlocal next_start_id
        filepath = raw_dir / f"master_hwpe_{master_idx}.txt"
        master = StimuliGenerator(IW, WIDTH_OF_MEMORY, N_BANKS, TOT_MEM_SIZE, HWPE_WIDTH * DATA_WIDTH, ADD_WIDTH,
                                   str(filepath), N_TEST_HWPE, EXACT_OR_MAX_OFFSET, CYCLE_OFFSET_HWPE, global_idx)
        config = str(master_config.get('mem_access_type', '0'))
        start_address = str(master_config.get('start_address', '0'))
        stride0 = int(master_config.get('stride0', 0))
        len_d0 = int(master_config.get('len_d0', 0))
        stride1 = int(master_config.get('stride1', 0))
        len_d1 = int(master_config.get('len_d1', 0))
        stride2 = int(master_config.get('stride2', 0))

        if config == '0':
            next_start_id = master.random_gen(next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        elif config == '1':
            next_start_id = master.linear_gen(stride0, start_address, next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        elif config == '2':
            next_start_id = master.gen_2d(stride0, len_d0, stride1, start_address, next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        elif config == '3':
            next_start_id = master.gen_3d(stride0, len_d0, stride1, len_d1, stride2, start_address, next_start_id, LIST_OF_FORBIDDEN_ADDRESSES_READ, LIST_OF_FORBIDDEN_ADDRESSES_WRITE)

    global_idx = 0
    # Generate logarithmic masters (CORE, DMA, EXT) in order
    for i in range(N_LOG):
        # determine class of this master (core/dma/ext)
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
        _generate_master(raw_dir / f"master_log_{i}.txt", master_cfg, is_hwpe=False, master_global_idx=global_idx)
        global_idx += 1

    # Generate HWPE masters; their global index follows the previous masters
    for hw_idx in range(N_HWPE):
        if HWPE_ZERO_FLAG:
            global_idx += 1
            continue
        master_cfg = hwpe_masters[hw_idx]
        _generate_master(raw_dir / f"master_hwpe_{hw_idx}.txt", master_cfg, is_hwpe=True, master_global_idx=global_idx)
        global_idx += 1

    print("STEP 0 COMPLETED: create raw txt files")

    # Process raw files
    simvector_raw_path = str(raw_dir)
    simvector_processed_path = str((raw_dir.parent / 'stimuli_processed').resolve())
    unfold_raw_txt(simvector_raw_path, simvector_processed_path, IW, DATA_WIDTH, ADD_WIDTH, HWPE_WIDTH)
    print("STEP 1 COMPLETED: unfold txt files")

    pad_txt_files(simvector_processed_path, IW, DATA_WIDTH, ADD_WIDTH, HWPE_WIDTH)
    print("STEP 2 COMPLETED: pad txt files")

    if args.golden:
        golden_dir = (generated_dir / 'golden').resolve()
        golden_dir.mkdir(parents=True, exist_ok=True)

        for stim_path in sorted(processed_dir.glob('master_*.txt')):
            try:
                text = stim_path.read_text(encoding='ascii')
            except OSError:
                continue

            if text.strip() == 'zero':
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

            (golden_dir / f"golden_{stim_path.name}").write_text("\n".join(out_lines) + ("\n" if out_lines else ""), encoding='ascii')
        print("STEP 3 COMPLETED: golden vectors")


if __name__ == '__main__':
    main()
