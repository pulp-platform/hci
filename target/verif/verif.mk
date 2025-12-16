# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE.solderpad for details.
# SPDX-License-Identifier: SHL-0.51
#
# Sergio Mazzola <smazzola@iis.ee.ethz.ch>

HCI_VERIF_DIR = $(HCI_ROOT)/target/verif

# Include generated Makefiles
include $(HCI_VERIF_DIR)/config/hardware.mk
include $(HCI_VERIF_DIR)/config/testbench.mk

# Bender targets and defines
include $(HCI_VERIF_DIR)/bender.mk

# Tooling
#NOTE: Only QuestaSim is currently supported by verification framework
SIM_QUESTA ?= questa-2022.3
SIM_VLIB ?= $(SIM_QUESTA) vlib
SIM_VSIM ?= $(SIM_QUESTA) vsim
SIM_VOPT ?= $(SIM_QUESTA) vopt

PYTHON ?= python3

##############
# Config gen #
##############

VERIF_CFG_JSON := $(HCI_VERIF_DIR)/config/hardware.json \
	$(HCI_VERIF_DIR)/config/testbench.json \
	$(HCI_VERIF_DIR)/config/workload.json

VERIF_CFG_MK := $(HCI_VERIF_DIR)/config/hardware.mk \
	$(HCI_VERIF_DIR)/config/testbench.mk

.PHONY: config-verif
config-verif: $(VERIF_CFG_MK)
# Generate Makefiles from JSON configs
$(HCI_VERIF_DIR)/config/%.mk: $(HCI_VERIF_DIR)/config/%.json $(HCI_VERIF_DIR)/config/%.mk.tpl $(HCI_VERIF_DIR)/config/json_to_mk.py
	python3 $(HCI_VERIF_DIR)/config/json_to_mk.py $* > $@

.PHONY: clean-config-verif
clean-config-verif:
	rm -rf $(VERIF_CFG_MK)

##################
# Simvectors gen #
##################

GEN_STIM_SCRIPT := $(HCI_VERIF_DIR)/stimuli_gen/main.py
STIM_SRC_FILES := $(shell find {$(HCI_VERIF_DIR)/config,$(HCI_VERIF_DIR)/stimuli_gen} -type f)

.PHONY: stim-verif
stim-verif: $(HCI_VERIF_DIR)/simvectors/.stim_stamp
$(HCI_VERIF_DIR)/simvectors/.stim_stamp: $(VERIF_CFG_JSON) $(STIM_SRC_FILES)
	$(PYTHON) $(GEN_STIM_SCRIPT) \
		--workload_config $(HCI_VERIF_DIR)/config/workload.json \
		--testbench_config $(HCI_VERIF_DIR)/config/testbench.json \
		--hardware_config $(HCI_VERIF_DIR)/config/hardware.json
	date > $@

.PHONY: clean-stim-verif
clean-stim-verif:
	rm -rf $(HCI_VERIF_DIR)/simvectors

##############
# Simulation #
##############

# Parameters
GUI ?= 0
# Top-level to simulate
sim_top_level ?= tb_hci
sim_vsim_lib ?= $(HCI_VERIF_DIR)/vsim/work

SIM_SRC_FILES = $(shell find {$(HCI_RTL_DIR),$(HCI_VERIF_DIR)/src} -type f)
SIM_QUESTA_SUPPRESS ?= -suppress 3009 -suppress 3053 -suppress 8885 -suppress 12003

# vlog compilation arguments
SIM_HCI_VLOG_ARGS ?=
SIM_HCI_VLOG_ARGS += -work $(sim_vsim_lib)
# SIM_HCI_VLOG_ARGS += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233
# vopt optimization arguments
SIM_HCI_VOPT_ARGS ?=
SIM_HCI_VOPT_ARGS += $(SIM_QUESTA_SUPPRESS) -work $(sim_vsim_lib)
# vsim simulation arguments
SIM_HCI_VSIM_ARGS ?=
SIM_HCI_VSIM_ARGS += $(SIM_QUESTA_SUPPRESS) -lib $(sim_vsim_lib) +permissive +notimingchecks +nospecify -t 1ps
ifeq ($(GUI),0)
	SIM_HCI_VSIM_ARGS += -c
endif

$(HCI_VERIF_DIR)/vsim/compile.tcl: $(HCI_ROOT)/Bender.lock $(HCI_ROOT)/Bender.yml $(HCI_ROOT)/bender.mk $(HCI_VERIF_DIR)/bender.mk $(SIM_SRC_FILES) $(VERIF_CFG_MK)
	mkdir -p $(HCI_VERIF_DIR)/vsim
	$(BENDER) script vsim $(COMMON_DEFS) $(VERIF_DEFS) $(COMMON_TARGS) $(VERIF_TARGS) --vlog-arg="$(SIM_HCI_VLOG_ARGS)" > $@

.PHONY: compile-verif
compile-verif: $(sim_vsim_lib)/.hw_compiled
$(sim_vsim_lib)/.hw_compiled: $(HCI_VERIF_DIR)/vsim/compile.tcl $(HCI_ROOT)/.bender/.checkout_stamp $(SIM_SRC_FILES)
	cd $(HCI_VERIF_DIR)/vsim && \
	$(SIM_VLIB) $(sim_vsim_lib) && \
	$(SIM_VSIM) -c -do 'quit -code [source $<]' && \
	date > $@

.PHONY: opt-verif
opt-verif: $(sim_vsim_lib)/$(sim_top_level)_optimized/.tb_opt_compiled
$(sim_vsim_lib)/$(sim_top_level)_optimized/.tb_opt_compiled: $(sim_vsim_lib)/.hw_compiled
	cd $(HCI_VERIF_DIR)/vsim && \
	$(SIM_VOPT) $(SIM_HCI_VOPT_ARGS) $(sim_top_level) -o $(sim_top_level)_optimized +acc && \
	date > $@

.PHONY: run-verif
run-verif: $(sim_vsim_lib)/$(sim_top_level)_optimized/.tb_opt_compiled $(HCI_VERIF_DIR)/simvectors/.stim_stamp
	cd $(HCI_VERIF_DIR)/vsim && \
	$(SIM_VSIM) $(SIM_HCI_VSIM_ARGS) \
	$(sim_top_level)_optimized \
	-do 'set GUI $(GUI); source $(HCI_VERIF_DIR)/vsim/$(sim_top_level).tcl'

.PHONY: clean-verif
clean-sim-verif:
	rm -rf $(HCI_VERIF_DIR)/vsim

###########
# Helpers #
###########

.PHONY: clean-verif
clean-verif: clean-config-verif clean-stim-verif clean-sim-verif
	find $(HCI_VERIF_DIR) -type d -name '__pycache__' -exec rm -rf {} +
