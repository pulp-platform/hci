##############################
# List of all HCI parameters #
##############################

#### PARAMETERS TO BE MAUALLY INSERTED ####

# Number of HWPEs attached to the port
N_HWPE=2
# Widht of an HWPE wide-word (as a multiple of DATA_WIDTH)
HWPE_WIDTH=4
# Number of Core ports                                                  
N_CORE=3
# Number of DMA ports                                                  
N_DMA=0
# Number of External ports                                               
N_EXT=0
# TEST_SET_BIT (for Log Interconnect)                   
TS_BIT=21
# FIFO Depth for HWPE Interconnect                            
EXPFIFO=0
# Log interconnect type selector
SEL_LIC=0  
# Width of DATA in bits                                                
DATA_WIDTH=32 
# Total memory size (kB)                                               
TOT_MEM_SIZE=32  
# Number of memory banks
N_BANKS=8
# Width of a memory bank (bits)                                                  
WIDTH_OF_MEMORY=32
# Invert default priority in the hci_arbiter module
INVERT_PRIO=1
# Maximum number of stalls in the lower priority channel of the hci_arbiter
LOW_PRIO_MAX_STALL=10