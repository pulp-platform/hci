#################################
# 		SIMULATION SETUP		#
#################################
# Can be used to measure bandwidth

# Number of transactions for each master in the log branch
N_TRANSACTION_LOG?=1000
# Ratio between the number of transactions for a master in the hwpe branch and log branch
TRANSACTION_RATIO?=1
# This three parameters define the maximum number of clock cycles between two consecutive requests coming from the same master
# If EXACT_OR_MAX_OFFSET = 0 ---> CYCLE_OFFSET defines the exact number of clock cycles between two consecutive requests
# If EXACT_OR_MAX_OFFSET = 1 ---> CYCLE_OFFSET defines the maximum number of clock cycles between two consecutive requests (the exact value is determined randomly)
# NOTE: the minimum value for CYCLE_OFFSET is 1
EXACT_OR_MAX_OFFSET?=0
CYCLE_OFFSET_LOG?=1
CYCLE_OFFSET_HWPE?=1
# Clock period in ns
CLK_PERIOD?=50
# Number of clock cycles after which the reset signal is deasserted
RST_CLK_CYCLES?=10
# Maximum expected number of cycles between the gnt signal and the r_valid signal
MAX_CYCLES_BETWEEN_GNT_RVALID?=1
# Flag for the random generation of the gnt signal (TCDM side)
RANDOM_GNT?=0
# Flag to activate the priority handling check, where it is consider as LOW_PRIO_MAX_STALL the maximum number of consecutive stalls on low-priority channel.
PRIORITY_CHECK_MODE_ONE?=0
# Flag to activate the priority handling check, where it is consider as LOW_PRIO_MAX_STALL the maximum number of consecutive cycles where there is at least 1 req both in the high and low priority channel
PRIORITY_CHECK_MODE_ZERO?=0
# Invert default priority in the hci_arbiter module
INVERT_PRIO?=0
# Maximum number of stalls in the lower priority channel of the hci_arbiter
LOW_PRIO_MAX_STALL?=10
