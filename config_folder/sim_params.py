#################################
# List of simulation parameters #
#################################

# Number of tests for each master
N_TEST=3 
# Maximum cycle offset: needed if you want to generate the list of the transaction with masters_main.py. It indicates the maximum number of clock cycles 
# between two consecutive requests coming from the same master. Note: the minimum value for this parameter is 1.
MAX_CYCLE_OFFSET=5
# Clock period in ns
CLK_PERIOD=50
# Application delay in ns
APPL_DELAY=0
# Number of clock cycles after which the reset signal is deasserted
RST_CLK_CYCLES=10