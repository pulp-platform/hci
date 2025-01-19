###########################################
#	  LOG3 MEMORY ACCESS PARAMETERS		  #
###########################################

# Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D)
MEM_ACCESS_TYPE_LOG3?=0
# Starting address in binary (required for linear, 2D, and 3D accesses). Leave it empty if not needed
START_ADDRESS_LOG3?=0
# Stride0 (required for linear, 2D, and 3D accesses). Leave it empty if not needed
STRIDE0_LOG3?=0
# Len_d0 (required for 2D and 3D accesses). Leave it empty if not needed
LEN_D0_LOG3?=0
# Stride1 (required for 2D and 3D accesses). Leave it empty if not needed
STRIDE1_LOG3?=0
# Len_d1 (required for 3D accesses). Leave it empty if not needed
LEN_D1_LOG3?=0
# Stride2 (required for 3D accesses). Leave it empty if not needed
STRIDE2_LOG3?=0
