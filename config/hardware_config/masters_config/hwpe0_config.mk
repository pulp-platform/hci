###########################################
#	  HWPE0 MEMORY ACCESS PARAMETERS	  #
###########################################

# Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D)
MEM_ACCESS_TYPE_HWPE0?=0
# Starting address in binary (required for linear, 2D, and 3D accesses). Leave it empty if not needed
START_ADDRESS_HWPE0?=0
# Stride0 (required for linear, 2D, and 3D accesses). Set to 0 if not needed
STRIDE0_HWPE0?=0
# Len_d0 (required for 2D and 3D accesses). Leave it empty if not needed
LEN_D0_HWPE0?=0
# Stride1 (required for 2D and 3D accesses). Leave it empty if not needed
STRIDE1_HWPE0?=0
# Len_d1 (required for 3D accesses). Leave it empty if not needed
LEN_D1_HWPE0?=0
# Stride2 (required for 3D accesses). Leave it empty if not needed
STRIDE2_HWPE0?=0
