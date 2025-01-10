#include config_folder/config.mk

#test:
#	echo $(ARGUMENT_PARAMETER)
#	$(python) --name $(ARGUMENT_PARAMETER)

ROOT_DIR      = $(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))) # set the absolute path of the directory where the makefile is located

CONFIG_FILE_HCI := config_folder/hci_params.py
CONFIG_FILE_SIM := config_folder/sim_params.py
#$(info ROOT_DIR: $(ROOT_DIR))
#$(info CONFIG_FILE_SIM: $(CONFIG_FILE_SIM))
VLIB ?= vlib
library ?= work
VSIM ?= vsim
top_level ?= hci_tb
VOPT ?= vopt

VLOG_ARGS += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233 -timescale \"1 ns / 1 ps\" \"+incdir+$(shell pwd)/include\"
MACROS_HCI += $(shell awk '!/^\#/ && NF {printf "\"+define+%s \"", $$0}' $(CONFIG_FILE_HCI))
MACROS_SIM += $(shell awk '!/^\#/ && NF {printf "\"+define+%s \"", $$0}' $(CONFIG_FILE_SIM))

PYTHON = python
PYTHON_STIMULI_SCRIPT = verif/stimuli_generator/stimuli_gen_main.py

N_CORE := $(shell grep -oP '^N_CORE=\K\d+' $(CONFIG_FILE_HCI))
N_DMA := $(shell grep -oP '^N_DMA=\K\d+' $(CONFIG_FILE_HCI))
N_EXT := $(shell grep -oP '^N_EXT=\K\d+' $(CONFIG_FILE_HCI))
N_HWPE := $(shell grep -oP '^N_HWPE=\K\d+' $(CONFIG_FILE_HCI))
N_LOG := $(shell echo $(N_CORE) + $(N_DMA) + $(N_EXT) | bc) 
define generate_vsim
	echo 'set ROOT [file normalize [file dirname [info script]]/$3]' > $1
	bender script vsim --vlog-arg="$(VLOG_ARGS)" $2 --vlog-arg=$(MACROS_HCI) --vlog-arg=$(MACROS_SIM) | grep -v "set ROOT" >> $1
	echo >> $1
endef
################
# Dependencies #
################

.PHONY: checkout
## Checkout/update dependencies using Bender
checkout:
	bender checkout
	touch Bender.lock
	make scripts/compile.tcl

Bender.lock:
	bender checkout
	touch Bender.lock


########################
# Build and simulation #
########################

# Python stimuli
clean_stimuli:
	rm -rf verif/simvectors


LOG_ARGS := $(foreach i, $(shell seq 0 $(shell echo $(N_LOG) - 1 | bc)), --master_log$(i) 0)
HWPE_ARGS := $(foreach i, $(shell seq 0 $(shell echo $(N_HWPE) - 1 | bc)), --master_hwpe$(i) 0)

setup_bandwidth: 
	sed -i 's/^MAX_CYCLE_OFFSET.*$$/MAX_CYCLE_OFFSET=1/' $(CONFIG_FILE_SIM)
	sed -i 's/^RANDOM_GNT.*$$/RANDOM_GNT=0/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ONE.*$$/PRIORITY_CHECK_MODE_ONE=0/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ZERO.*$$/PRIORITY_CHECK_MODE_ZERO=0/' $(CONFIG_FILE_SIM)

setup_data_integ:
	sed -i 's/^MAX_CYCLE_OFFSET.*$$/MAX_CYCLE_OFFSET=7/' $(CONFIG_FILE_SIM)
	sed -i 's/^RANDOM_GNT.*$$/RANDOM_GNT=1/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ONE.*$$/PRIORITY_CHECK_MODE_ONE=0/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ZERO.*$$/PRIORITY_CHECK_MODE_ZERO=0/' $(CONFIG_FILE_SIM)
setup_arbiter_stall:
	sed -i 's/^MAX_CYCLE_OFFSET.*$$/MAX_CYCLE_OFFSET=7/' $(CONFIG_FILE_SIM)
	sed -i 's/^RANDOM_GNT.*$$/RANDOM_GNT=1/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ONE.*$$/PRIORITY_CHECK_MODE_ONE=1/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ZERO.*$$/PRIORITY_CHECK_MODE_ZERO=0/' $(CONFIG_FILE_SIM)

setup_arbiter_no_stall:
	sed -i 's/^MAX_CYCLE_OFFSET.*$$/MAX_CYCLE_OFFSET=7/' $(CONFIG_FILE_SIM)
	sed -i 's/^RANDOM_GNT.*$$/RANDOM_GNT=1/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ONE.*$$/PRIORITY_CHECK_MODE_ONE=0/' $(CONFIG_FILE_SIM)
	sed -i 's/^PRIORITY_CHECK_MODE_ZERO.*$$/PRIORITY_CHECK_MODE_ZERO=1/' $(CONFIG_FILE_SIM)


stimuli: clean_stimuli
	$(PYTHON) $(PYTHON_STIMULI_SCRIPT) $(LOG_ARGS) $(HWPE_ARGS)


# Questasim simulation
clean:
	rm -rf scripts/compile.tcl
	rm -rf work

scripts/compile.tcl: | Bender.lock
	$(call generate_vsim, $@, -t test ,..) 

$(library):
	$(VLIB) $(library)

compile: $(library) scripts/compile.tcl
	@test -f Bender.lock || { echo "ERROR: Bender.lock file does not exist. Did you run make checkout in bender mode?"; exit 1; }
	@test -f scripts/compile.tcl || { echo "ERROR: scripts/compile.tcl file does not exist. Did you run make scripts in bender mode?"; exit 1; }
	$(VSIM) -c -do 'source scripts/compile.tcl; quit' -msgmode both

build: compile
	$(VOPT) $(compile_flag) -suppress 3053 -suppress 8885 -work $(library)  $(top_level) -o $(top_level)_optimized -debug


run:
	$(VSIM) +permissive $(questa-flags) $(questa-cmd) -suppress 3053 -suppress 8885 -lib $(library)  +MAX_CYCLES=$(max_cycles) +UVM_TESTNAME=$(test_case) +APP=$(elf-bin) +notimingchecks +nospecify  -t 1ps \
	${top_level}_optimized +permissive-off ++$(elf-bin) ++$(target-options) ++$(cl-bin) | tee sim.log
