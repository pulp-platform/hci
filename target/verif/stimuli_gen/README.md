# HCI Stimuli Generator

Python package for generating test stimuli for the HCI verification environment.

## Usage

### Generate Stimuli

```bash
python verif/stimuli_gen/main.py --sim_and_hardware_params <params> --master_log <params> --master_hwpe <params>
```

Or use the Makefile:
```bash
make stimuli
```

## Configuration

Configuration files are located in `target/verif/config/`:
- `hardware.json` - HCI hardware parameters (auto-generates `hardware.mk`)
- `testbench.json` - Testbench parameters (auto-generates `testbench.mk`)
- `workload.json` - Workload configuration with simulation parameters and master-specific settings
