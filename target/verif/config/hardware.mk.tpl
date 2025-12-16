# Copyright 2025 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE.solderpad for details.
# SPDX-License-Identifier: SHL-0.51
#
# This file is auto-generated from hardware.json - DO NOT EDIT MANUALLY

# Hardware configuration parameters (from hardware.json)
N_HWPE?=${N_HWPE}
HWPE_WIDTH?=${HWPE_WIDTH}
N_CORE?=${N_CORE}
N_DMA?=${N_DMA}
N_EXT?=${N_EXT}
TS_BIT?=${TS_BIT}
EXPFIFO?=${EXPFIFO}
SEL_LIC?=${SEL_LIC}
DATA_WIDTH?=${DATA_WIDTH}
TOT_MEM_SIZE?=${TOT_MEM_SIZE}
N_BANKS?=${N_BANKS}

# Derived: Total number of log branch masters (CORE + DMA + EXT)
N_LOG := $$(strip $$(shell echo $$(N_CORE) + $$(N_DMA) + $$(N_EXT) | bc))
