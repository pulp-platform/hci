# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE.solderpad for details.
# SPDX-License-Identifier: SHL-0.51
#
# Sergio Mazzola <smazzola@iis.ee.ethz.ch>

HCI_VERIF_DIR      = $(HCI_ROOT)/target/verif
HCI_VERIF_EXPL_DIR = $(HCI_VERIF_DIR)/exploration

################
# Benchmarking #
################

# Hardware × Testbench sweep (per workload, separate result directories).
# To fix a dimension, set the corresponding variable to a single file path.
HW_TB_SWEEP_SCRIPT := $(HCI_VERIF_EXPL_DIR)/scripts/run_hw_tb_sweep.sh

# Results root — one subdirectory will be created per workload
RESULTS_DIR ?= $(HCI_VERIF_EXPL_DIR)/results

# Glob patterns (or single paths) for configs to sweep
SWEEP_HARDWARE_CFG  ?= $(HCI_VERIF_EXPL_DIR)/config/hardware/hardware_*.json
SWEEP_TESTBENCH_CFG ?= $(HCI_VERIF_EXPL_DIR)/config/testbench/testbench_*.json
SWEEP_WORKLOADS_CFG ?= $(HCI_VERIF_EXPL_DIR)/config/workloads/workload_transformer_block.json

# Hardware config used for the ideal (no-stall) reference run
IDEAL_HARDWARE_CFG ?= $(HCI_VERIF_EXPL_DIR)/config/hardware/hardware_hci_2hwpe_8fact.json

hw-tb-sweep:
	bash $(HW_TB_SWEEP_SCRIPT) \
	  --results-dir       "$(RESULTS_DIR)" \
	  --hardware-pattern  "$(SWEEP_HARDWARE_CFG)" \
	  --testbench-pattern "$(SWEEP_TESTBENCH_CFG)" \
	  --workloads         "$(SWEEP_WORKLOADS_CFG)" \
	  --ideal-hardware    "$(IDEAL_HARDWARE_CFG)"
