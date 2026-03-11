# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE.solderpad for details.
# SPDX-License-Identifier: SHL-0.51
#
# Sergio Mazzola <smazzola@iis.ee.ethz.ch>

HCI_VERIF_EXPL_DIR = $(HCI_ROOT)/target/verif/exploration

################
# Benchmarking #
################

# Modify this script to configure parameters (e.g., workload to run)
BENCHMARK_SCRIPT := $(HCI_VERIF_EXPL_DIR)/scripts/run_sweep.sh

benchmarking-sweep:
	. $(BENCHMARK_SCRIPT)