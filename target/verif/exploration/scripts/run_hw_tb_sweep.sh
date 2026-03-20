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

# -----------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --results-dir PATH          Root directory for results (default: exploration/results)"
  echo "  --hardware-pattern GLOB     Glob (or single path) for hardware config files to sweep"
  echo "  --testbench-pattern GLOB    Glob (or single path) for testbench config files to sweep"
  echo "  --workloads GLOB            Glob (or single path) for workload JSON files to run"
  echo "  --ideal-hardware PATH       Hardware config used for the ideal reference run"
  echo "  -h, --help                  Show this help message"
  exit 0
}

RESULTS_DIR=""
HARDWARE_PATTERN=""
TESTBENCH_PATTERN=""
WORKLOADS=""
IDEAL_HARDWARE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results-dir)       RESULTS_DIR="$2";       shift 2 ;;
    --hardware-pattern)  HARDWARE_PATTERN="$2";  shift 2 ;;
    --testbench-pattern) TESTBENCH_PATTERN="$2"; shift 2 ;;
    --workloads)         WORKLOADS="$2";         shift 2 ;;
    --ideal-hardware)    IDEAL_HARDWARE="$2";    shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Apply defaults for anything not passed on the command line
RESULTS_DIR=${RESULTS_DIR:-$VERIF_EXPL_DIR/results}
HARDWARE_PATTERN=${HARDWARE_PATTERN:-$VERIF_EXPL_DIR/config/hardware/hardware_*.json}
TESTBENCH_PATTERN=${TESTBENCH_PATTERN:-$VERIF_EXPL_DIR/config/testbench/testbench_*.json}
WORKLOADS=${WORKLOADS:-$VERIF_EXPL_DIR/config/workloads/workload_*.json}
IDEAL_HARDWARE=${IDEAL_HARDWARE:-$VERIF_EXPL_DIR/config/hardware/hardware_hci_2hwpe_8fact.json}

# Common Makefile settings (verif.mk)
export GUI=0

mkdir -p "$RESULTS_DIR"

# Expand glob patterns into arrays (single paths work identically to 1-element globs)
hw_configs=( $HARDWARE_PATTERN )
tb_configs=( $TESTBENCH_PATTERN )
workload_list=( $WORKLOADS )

# -----------------------------------------------------------------------
# Main sweep: per workload → per hardware config → per testbench config
# -----------------------------------------------------------------------
for workload_json in "${workload_list[@]}"; do
  workload_name=$(basename "$workload_json" .json)
  # Skip *_ideal workloads (they are run separately below)
  if [[ "$workload_name" == *_ideal ]]; then
    continue
  fi

  workload_results_dir=$RESULTS_DIR/$workload_name
  mkdir -p "$workload_results_dir"

  echo -e "\033[34;1m========================================\033[0m"
  echo -e "\033[34;1mWorkload: $workload_name\033[0m"
  echo -e "\033[34;1m========================================\033[0m"

  export WORKLOAD_JSON="$workload_json"

  for hardware_config in "${hw_configs[@]}"; do
    hw_name=$(basename "$hardware_config" .json)

    # LOG topology is not affected by QoS/priority testbench settings: run once
    # with the default testbench, mirroring the ideal-run treatment.
    if [[ "$hw_name" == *_log_* ]]; then
      make clean-verif
      echo -e "\033[32;1mRunning: hw=$hw_name  tb=default (LOG topology — TB sweep skipped)\033[0m"
      export HARDWARE_JSON="$hardware_config"
      export TESTBENCH_JSON="$VERIF_DIR/config/testbench.json"
      make run-verif
      python3 $VERIF_EXPL_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out "$workload_results_dir/${hw_name}.json"
      cp $VERIF_DIR/simvectors/generated/dataflow.html "$workload_results_dir/${hw_name}.html"
      continue
    fi

    for testbench_config in "${tb_configs[@]}"; do
      tb_name=$(basename "$testbench_config" .json)
      run_name="${hw_name}_${tb_name}"

      make clean-verif
      echo -e "\033[32;1mRunning: hw=$hw_name  tb=$tb_name\033[0m"
      # Run the simulation with the current config combination
      export HARDWARE_JSON="$hardware_config"
      export TESTBENCH_JSON="$testbench_config"
      make run-verif
      # Parse vsim results and save
      python3 $VERIF_EXPL_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out "$workload_results_dir/${run_name}.json"
      cp $VERIF_DIR/simvectors/generated/dataflow.html "$workload_results_dir/${run_name}.html"
    done
  done

  # -------------------------------------------------------------------
  # Ideal run: use the matching *_ideal workload (if it exists)
  # -------------------------------------------------------------------
  ideal_workload_json="${workload_json%.*}_ideal.json"
  if [ -f "$ideal_workload_json" ]; then
    make clean-verif
    echo -e "\033[32;1mRunning ideal simulation for workload: $workload_name\033[0m"
    export WORKLOAD_JSON="$ideal_workload_json"
    export HARDWARE_JSON="$IDEAL_HARDWARE"
    # No need to set TESTBENCH_JSON (use last one from the sweep): ideal run must not contain interference, so QoS settings should not matter
    make run-verif
    python3 $VERIF_EXPL_DIR/scripts/parse_vsim.py --transcript $VERIF_DIR/vsim/transcript --out "$workload_results_dir/ideal.json"
    cp $VERIF_DIR/simvectors/generated/dataflow.html "$workload_results_dir/ideal.html"
    # Generate plots with ideal comparison
    python3 $VERIF_EXPL_DIR/scripts/plot_sweep_results.py --results-dir "$workload_results_dir" --ideal-run "$workload_results_dir/ideal.json"
  else
    echo -e "\033[33;1mWarning: Ideal workload JSON $ideal_workload_json not found. Skipping ideal simulation.\033[0m"
    # Generate plots without ideal comparison
    python3 $VERIF_EXPL_DIR/scripts/plot_sweep_results.py --results-dir "$workload_results_dir"
  fi

  echo -e "\033[34;1mResults for $workload_name saved to: $workload_results_dir\033[0m"
done
