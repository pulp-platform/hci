#!/bin/bash

set -e

# Make sure we are in hci root
if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null) || [ "$(basename "$git_root")" != "hci" ]; then
  echo "Error: This script must be run from within the hci project git repository." >&2
  exit 1
fi
cd "$git_root"

VERIF_DIR=./target/verif
RESULTS_DIR=$VERIF_DIR/results
PLOTS_DIR=$RESULTS_DIR/plots

mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR"/hardware_*.json

# For each hardware*.json in target/verif/config/sweep_hardware, run simulation and parse transcript
for hardware_config in $VERIF_DIR/config/sweep_hardware/hardware_*.json; do
  make clean-verif
  echo "Running simulation with hardware config: $hardware_config"
  HARDWARE_JSON="$hardware_config" GUI=0 make run-verif
  python3 $VERIF_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out "$RESULTS_DIR"/$(basename "$hardware_config" .json).json
done

python3 $VERIF_DIR/scripts/plot_sweep_results.py --results-dir "$RESULTS_DIR" --out-dir "$PLOTS_DIR"
