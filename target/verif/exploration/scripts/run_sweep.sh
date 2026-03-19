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

RUN_NAME=transformer_block

# Makefile settings (verif.mk)
export GUI=0
export WORKLOAD_JSON=$VERIF_EXPL_DIR/config/workloads/workload_transformer_block.json
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

# Take the same WORKLOAD_JSON but append _ideal before .json
export WORKLOAD_JSON=${WORKLOAD_JSON%.*}_ideal.json
# For the hardware config, use HCI
export HARDWARE_JSON=$VERIF_EXPL_DIR/config/hardware/hardware_hci_2hwpe_8fact.json

# If WORKLOAD_JSON exists, run ideal simulation and parse transcript
if [ -f "$WORKLOAD_JSON" ]; then
  make clean-verif
  echo -e "\033[32;1mRunning ideal simulation with workload config: $WORKLOAD_JSON; hardware config: $HARDWARE_JSON\033[0m"
  make run-verif
  python3 $VERIF_EXPL_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out $RESULTS_DIR/$RUN_NAME/ideal.json
  cp $VERIF_DIR/simvectors/generated/dataflow.html $RESULTS_DIR/$RUN_NAME/ideal.html
  # Generate plots considering ideal workload runtime
  python3 $VERIF_EXPL_DIR/scripts/plot_sweep_results.py --results-dir $RESULTS_DIR/$RUN_NAME --out-dir $RESULTS_DIR/$RUN_NAME --ideal-run $RESULTS_DIR/$RUN_NAME/ideal.json
else
  echo -e "\033[31;1mWarning: Ideal workload JSON $WORKLOAD_JSON not found. Skipping ideal simulation.\033[0m"
  echo -e "\033[31;1mGenerate the ideal workload JSON $WORKLOAD_JSON to enable ideal simulation and comparison.\033[0m"
  # Generate plots without ideal workload runtime comparison
  python3 $VERIF_EXPL_DIR/scripts/plot_sweep_results.py --results-dir $RESULTS_DIR/$RUN_NAME --out-dir $RESULTS_DIR/$RUN_NAME
fi
