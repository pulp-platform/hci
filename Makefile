include config/config.mk

ROOT_DIR := $(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))) # set the absolute path of the directory where the makefile is located
VLIB ?= vlib
library ?= work
VSIM ?= vsim
top_level ?= hci_tb
VOPT ?= vopt
PYTHON ?= python
PYTHON_STIMULI_SCRIPT ?= verif/stimuli_generator/stimuli_gen_main.py
N_LOG := $(shell echo $(N_CORE) + $(N_DMA) + $(N_EXT) | bc) 

VLOG_ARGS += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233 -timescale \"1 ns / 1 ps\" \"+incdir+$(shell pwd)/include\"
MACROS_TB := $(N_HWPE) $(HWPE_WIDTH) $(N_CORE) $(N_DMA) $(N_EXT) $(TS_BIT) $(EXPFIFO) $(SEL_LIC) $(DATA_WIDTH) $(TOT_MEM_SIZE) $(N_BANKS) $(WIDTH_OF_MEMORY) \
$(N_TEST) $(TEST_RATIO) $(CLK_PERIOD) $(RST_CLK_CYCLES) $(MAX_CYCLES_BETWEEN_GNT_RVALID) $(RANDOM_GNT) $(PRIORITY_CHECK_MODE_ONE) $(PRIORITY_CHECK_MODE_ZERO) $(MAX_CYCLE_OFFSET) $(INVERT_PRIO) $(LOW_PRIO_MAX_STALL)
define generate_vsim
	echo 'set ROOT [file normalize [file dirname [info script]]/$3]' > $1
	bender script vsim --vlog-arg="$(VLOG_ARGS)" $2 --vlog-arg=$(MACROS_TB) | grep -v "set ROOT" >> $1
	echo >> $1
endef

########################
# 	  DEPENDENCIES     #
########################

.PHONY: checkout
## Checkout/update dependencies using Bender
checkout:
	bender checkout
	touch Bender.lock
	make scripts/compile.tcl

Bender.lock:
	bender checkout
	touch Bender.lock

# Create config files for the masters
clean_setup:
	rm -rf config/hardware_config/masters_config

setup: clean_setup
	@for i in $(shell seq 0 $(shell echo $(N_LOG)-1 | bc) ); do \
		LOG_PATH="config/hardware_config/masters_config/log"$$i"_config.mk"; \
		echo "Creating log"$$i"_config.mk..."; \
		mkdir -p config/hardware_config/masters_config; \
		echo "###########################################" > $$LOG_PATH;  \
		echo "#	  LOG$$i MEMORY ACCESS PARAMETERS		  #" >> $$LOG_PATH; \
		echo "###########################################"	>> $$LOG_PATH; \
		echo -e "\n# Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D)" >> $$LOG_PATH; \
		echo "MEM_ACCESS_TYPE_LOG$$i?=" >> $$LOG_PATH; \
		echo "# Starting address in binary (required for linear, 2D, and 3D accesses). Set to 0 if not needed" >> $$LOG_PATH; \
		echo "START_ADDRESS_LOG$$i?=" >> $$LOG_PATH; \
		echo "# Stride0 (required for linear, 2D, and 3D accesses). Set to 0 if not needed" >> $$LOG_PATH; \
		echo "STRIDE0_LOG$$i?=" >> $$LOG_PATH; \
		echo "# Len_d0 (required for 2D and 3D accesses). Set to 0 if not needed" >> $$LOG_PATH; \
		echo "LEN_D0_LOG$$i?=" >> $$LOG_PATH; \
		echo "# Stride1 (required for 2D and 3D accesses). Set to 0 if not needed" >> $$LOG_PATH; \
		echo "STRIDE1_LOG$$i?=" >> $$LOG_PATH; \
		echo "# Len_d1 (required for 3D accesses). Set to 0 if not needed" >> $$LOG_PATH; \
		echo "LEN_D1_LOG$$i?=" >> $$LOG_PATH;  \
		echo "# Stride2 (required for 3D accesses). Set to 0 if not needed" >> $$LOG_PATH;  \
		echo "STRIDE2_LOG$$i?=" >> $$LOG_PATH; \
		echo "Done!";\
	done
	@for i in $(shell seq 0 $(shell echo $(N_HWPE)-1 | bc) ); do \
		HWPE_PATH="config/hardware_config/masters_config/hwpe"$$i"_config.mk"; \
		echo "Creating hwpe"$$i"_config.mk..."; \
		mkdir -p config/hardware_config/masters_config; \
		echo "###########################################" > $$HWPE_PATH;  \
		echo "#	  HWPE$$i MEMORY ACCESS PARAMETERS	  #" >> $$HWPE_PATH; \
		echo "###########################################"	>> $$HWPE_PATH; \
		echo -e "\n# Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D)" >> $$HWPE_PATH; \
		echo "MEM_ACCESS_TYPE_HWPE$$i?=" >> $$HWPE_PATH; \
		echo "# Starting address in binary (required for linear, 2D, and 3D accesses). Set to 0 if not needed" >> $$HWPE_PATH; \
		echo "START_ADDRESS_HWPE$$i?=" >> $$HWPE_PATH; \
		echo "# Stride0 (required for linear, 2D, and 3D accesses). Set to 0 if not needed" >> $$HWPE_PATH; \
		echo "STRIDE0_HWPE$$i?=" >> $$HWPE_PATH; \
		echo "# Len_d0 (required for 2D and 3D accesses). Set to 0 if not needed" >> $$HWPE_PATH; \
		echo "LEN_D0_HWPE$$i?=" >> $$HWPE_PATH; \
		echo "# Stride1 (required for 2D and 3D accesses). Set to 0 if not needed" >> $$HWPE_PATH; \
		echo "STRIDE1_HWPE$$i?=" >> $$HWPE_PATH; \
		echo "# Len_d1 (required for 3D accesses). Set to 0 if not needed" >> $$HWPE_PATH; \
		echo "LEN_D1_HWPE$$i?=" >> $$HWPE_PATH;  \
		echo "# Stride2 (required for 3D accesses). Set to 0 if not needed" >> $$HWPE_PATH;  \
		echo "STRIDE2_HWPE$$i?=" >> $$HWPE_PATH; \
		echo "Done!";\
	done


########################
# 	 CREATE STIMULI    #
########################

clean_stimuli:
	rm -rf verif/simvectors

PYTHON_SIM_AND_HARDWARE_ARGS := --sim_and_hardware_params $(N_BANKS) $(TOT_MEM_SIZE) $(WIDTH_OF_MEMORY) $(N_CORE) $(N_DMA) $(N_EXT) $(N_HWPE) $(HWPE_WIDTH) $(TEST_RATIO) $(N_TEST_LOG) $(MAX_CYCLE_OFFSET)
PYTHON_LOG_ARGS := $(foreach i, $(shell seq 0 $(shell echo $(N_LOG) - 1 | bc)), --master_log $(MEM_ACCESS_TYPE_LOG$(i)) $(START_ADDRESS_LOG$(i)) $(STRIDE0_LOG$(i)) $(LEN_D0_LOG$(i)) $(STRIDE1_LOG$(i)) $(LEN_D1_LOG$(i)) $(STRIDE2_LOG$(i)))
PYTHON_HWPE_ARGS := $(foreach i, $(shell seq 0 $(shell echo $(N_HWPE) - 1 | bc)), --master_hwpe $(MEM_ACCESS_TYPE_HWPE$(i)) $(START_ADDRESS_HWPE$(i)) $(STRIDE0_HWPE$(i)) $(LEN_D0_HWPE$(i)) $(STRIDE1_HWPE$(i)) $(LEN_D1_HWPE$(i)) $(STRIDE2_HWPE$(i)))

stimuli: clean_stimuli
	$(PYTHON) $(PYTHON_STIMULI_SCRIPT) $(PYTHON_SIM_AND_HARDWARE_ARGS) $(PYTHON_LOG_ARGS) $(PYTHON_HWPE_ARGS)

########################
#  BUILD AND SIMULATE  #
########################

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
