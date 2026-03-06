# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE.solderpad for details.
# SPDX-License-Identifier: SHL-0.51
#
# Sergio Mazzola <smazzola@iis.ee.ethz.ch>

# Common defines for bender
VERIF_DEFS ?=
VERIF_DEFS += \
	-D N_HWPE=$(N_HWPE) \
	-D HWPE_WIDTH_FACT=$(HWPE_WIDTH_FACT) \
	-D N_CORE=$(N_CORE) \
	-D N_DMA=$(N_DMA) \
	-D N_EXT=$(N_EXT) \
	-D DATA_WIDTH=$(DATA_WIDTH) \
	-D TOT_MEM_SIZE=$(TOT_MEM_SIZE) \
	-D N_BANKS=$(N_BANKS) \
	-D TS_BIT=$(TS_BIT) \
	-D EXPFIFO=$(EXPFIFO) \
	-D SEL_LIC=$(SEL_LIC) \
	-D CLK_PERIOD=$(CLK_PERIOD) \
	-D RST_CLK_CYCLES=$(RST_CLK_CYCLES) \
	-D RANDOM_GNT=$(RANDOM_GNT) \
	-D INTERCO_TYPE=$(INTERCO_TYPE) \
	-D INVERT_PRIO=$(INVERT_PRIO) \
	-D LOW_PRIO_MAX_STALL=$(LOW_PRIO_MAX_STALL) \

# Common targets for bender
VERIF_TARGS ?=
VERIF_TARGS += -t hci_verif
