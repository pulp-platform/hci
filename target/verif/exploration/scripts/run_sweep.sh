#!/bin/bash

set -e

# Make sure we are in hci root
if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null) || [ "$(basename "$git_root")" != "hci" ]; then
  echo "Error: This script must be run from within the hci project git repository." >&2
  exit 1
fi
cd "$git_root"

# Directories
VERIF_DIR=./target/verif
VERIF_EXPL_DIR=$VERIF_DIR/exploration
RESULTS_DIR=$VERIF_EXPL_DIR/results
PLOTS_DIR=$RESULTS_DIR/plots

RUN_NAME=gemm_cores_double_buffer

# Makefile settings (verif.mk)
export GUI=0
export WORKLOAD_JSON=$VERIF_EXPL_DIR/config/workloads/workload_dma_gemm_cores.json
export TESTBENCH_JSON=$VERIF_DIR/config/testbench.json
# HARDWARE_JSON is swept in the loop below

mkdir -p "$RESULTS_DIR"

# For each hardware*.json, run simulation and parse transcript
for hardware_config in $VERIF_EXPL_DIR/config/hardware/hardware_*.json; do
  make clean-verif
  echo -e "\033[32;1mRunning simulation with hardware config: $hardware_config\033[0m"
  export HARDWARE_JSON="$hardware_config"
  make run-verif
  python3 $VERIF_EXPL_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out $RESULTS_DIR/$RUN_NAME/$(basename "$hardware_config" .json).json
  # Copy html report
  cp $VERIF_DIR/simvectors/generated/dataflow.html $RESULTS_DIR/$RUN_NAME/$(basename "$hardware_config" .json).html
done

python3 $VERIF_EXPL_DIR/scripts/plot_sweep_results.py --results-dir $RESULTS_DIR/$RUN_NAME --out-dir $RESULTS_DIR/$RUN_NAME

# Ideal run (manual)
# do not forget to change IDEAL_WORKLOAD_RUNTIME in plot_sweep_results.py
python3 $VERIF_EXPL_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out $RESULTS_DIR/$RUN_NAME/ideal.json
cp $VERIF_DIR/simvectors/generated/dataflow.html $RESULTS_DIR/$RUN_NAME/ideal.html
# Regenerate plots with correct IDEAL_WORKLOAD_RUNTIME
python3 $VERIF_EXPL_DIR/scripts/plot_sweep_results.py --results-dir $RESULTS_DIR/$RUN_NAME --out-dir $RESULTS_DIR/$RUN_NAME
