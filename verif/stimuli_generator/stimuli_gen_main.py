####################################################
#   STIMULI GENERATOR for HCI verification suite   #
####################################################
#
# INTRODUCTION: 
#
# This code is used to generate the stimuli for the verification suite of the Heterogeneous Cluster Interconnect.
# Depending on a set of configuration parameters, this code will generate many different .txt files, one for each master and each containing
# a list of all the transactions that will occur during the simulation. These .txt files will be used by the application drivers in the verification suite
# to emulate the behaviour of a multi-master system
#
# USAGE GUIDE:
# 
# 1) Set the correct parameters in the files hci_params.py and sim_params.py
# 
# 2) Run the command 'python stimuli_gen_main.py', specifying the necessary arguments.
# Each argument is used to define the memory access type of a master, in particular it is possible to specify:
#   - Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D)
#   - Starting address in binary (required for linear, 2D, and 3D accesses)
#   - Stride0 (required for linear, 2D, and 3D accesses)
#   - Len_d0 (required for 2D and 3D accesses)
#   - Stride1 (required for 2D and 3D accesses)
#   - Len_d1 (required for 3D accesses)
#   - Stride2 (required for 3D accesses)
# note: There is no need to specify the "outer" length for linear, 2D, and 3D accesses,
# as the program will automatically stop once the specified `N_TEST` vectors are reached.
# 
# For the masters in the logarithmic branch, use --master_log0 --master_log1 --master_log2 ecc...
# The first arguments are used for the cores, then dma and ext.
# For the masters in the hwpe branch (shallow interconnect), use --master_hwpe0 --master_hwpe1 ecc...
#
# EXAMPLE:
# N_CORE = 1, N_DMA = 0, N_EXT = 1
# python stimuli_gen_main.py --master_log0 0, --master_log1 1 0101001 2 --master_hwpe1 2 1100100 2 3 10
# Running the script with these arguments will produce 3 .txt file, each containing:
# - stimuli with random memory access pattern (CORE)
# - stimuli with linear memory access pattern, starting address 0101001 and stride0 = 2 (EXT)
# - stimuli with a 2D memory access pattern, starting address 1100100, stride0 = 2, led_d0 = 3, stride2 = 2 (HWPE)
#
# "MAKE" YOUR LIFE EASIER:
# You can also use the makefile to configure the verification setup and automatically generate the correct stimuli for the most common scenarios. Otherwise, if a finer
# and more specific simulation is needed, you can manually invoke this script.

### LIBRARIES AND DEPENDENCIES ###
import random
import os
from pathlib import Path
import sys
import numpy as np
from classes_and_functions.class_stimuli_generator import stimuli_generator
import classes_and_functions.process_txt as process
code_directory = os.path.dirname(os.path.abspath(__file__))
config_directory = os.path.abspath(os.path.join(code_directory, "../../config_folder"))
sys.path.append(config_directory)
import argparse 

### ARGPARSE ###
parser = argparse.ArgumentParser(description="This script generates .txt files containing stimuli for use in the HCI verification suite.\n\n"
                                 "USAGE EXAMPLE:\n"
                                 "python stimuli_gen_main.py --master_log0 0, --master_log1 1 0101001 2 --master_hwpe0 2 1001010 3 10 2",
                                 formatter_class=argparse.RawTextHelpFormatter,)

parser.add_argument(f'--sim_and_hardware_params', nargs='+', default=[], required=True, type=int, help=f"Specify the software and hardware parameters used to generate the stimuli:\n"
                                                                                                                "   - N_BANKS \n"
                                                                                                                "   - TOT_MEM_SIZE \n"
                                                                                                                "   - WIDTH_OF_MEMORY \n"
                                                                                                                "   - N_CORE \n"
                                                                                                                "   - N_DMA \n"
                                                                                                                "   - N_EXT \n"
                                                                                                                "   - N_LOG \n"
                                                                                                                "   - N_HWPE\n"
                                                                                                                "   - HWPE_WIDTH\n"
                                                                                                                "   - TEST_RATIO\n"
                                                                                                                "   - N_TEST_LOG\n"
                                                                                                                "   - CYCLE_OFFSET")

parser.add_argument(f'--master_log', nargs='*', default=[], action="extend", help=f"Specify the parameters for memory access related to masters in log branch:\n"
                                                                                            "   - Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D) \n"
                                                                                            "   - Starting address in binary (required for linear, 2D, and 3D accesses)\n"
                                                                                            "   - Stride0 (required for linear, 2D, and 3D accesses)\n"
                                                                                            "   - Len_d0 (required for 2D and 3D accesses)\n"
                                                                                            "   - Stride1 (required for 2D and 3D accesses)\n"
                                                                                            "   - Len_d1 (required for 3D accesses)\n"
                                                                                            "   - Stride2 (required for 3D accesses)\n\n"
                                                                                            "NOTE: There is no need to specify the \"outer\" length for linear, 2D, and 3D accesses,\n"
                                                                                            "as the program will automatically stop once the specified `N_TEST` vectors are reached.")

parser.add_argument(f'--master_hwpe', nargs='*', default=[], action="extend", help=f"Specify the parameters for memory access related to masters in hwpe branch:\n"
                                                                                            "   - Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D) \n"
                                                                                            "   - Starting address in binary (required for linear, 2D, and 3D accesses)\n"
                                                                                            "   - Stride0 (required for linear, 2D, and 3D accesses)\n"
                                                                                            "   - Len_d0 (required for 2D and 3D accesses)\n"
                                                                                            "   - Stride1 (required for 2D and 3D accesses)\n"
                                                                                            "   - Len_d1 (required for 3D accesses)\n"
                                                                                            "   - Stride2 (required for 3D accesses)\n\n"
                                                                                            "NOTE: There is no need to specify the \"outer\" length for linear, 2D, and 3D accesses,\n"
                                                                                            "as the program will automatically stop once the specified `N_TEST` vectors are reached.")

args = parser.parse_args()

### PARAMETERS ###
N_BANKS, TOT_MEM_SIZE, WIDTH_OF_MEMORY, N_CORE, N_DMA,\
N_EXT, N_HWPE, HWPE_WIDTH, TEST_RATIO,\
N_TEST_LOG, CYCLE_OFFSET_LOG, CYCLE_OFFSET_HWPE, EXACT_OR_MAX_OFFSET= getattr(args,"sim_and_hardware_params")
WIDTH_OF_MEMORY_BYTE = WIDTH_OF_MEMORY/8
N_WORDS = (TOT_MEM_SIZE*1000/N_BANKS)/WIDTH_OF_MEMORY_BYTE
ADD_WIDTH = int(np.ceil(np.log2(TOT_MEM_SIZE*1000))) # Each memory address point to a byte
DATA_WIDTH = WIDTH_OF_MEMORY
N_TEST_HWPE = int(N_TEST_LOG*TEST_RATIO)
N_LOG = N_CORE + N_DMA + N_EXT
N_MASTER = N_LOG + N_HWPE
IW = int(np.ceil(np.log2(N_TEST_LOG*N_LOG + N_TEST_HWPE*N_HWPE)))
CORE_ZERO_FLAG = 0 
EXT_ZERO_FLAG = 0
DMA_ZERO_FLAG = 0
HWPE_ZERO_FLAG = 0

### CHECKS ###
if (not N_WORDS.is_integer()):
    print("ERROR: the number of words is not an integer value")
    sys.exit(1)
if (N_MASTER < 1):
    print("ERROR: the number of masters must be > 0")
    sys.exit(1)
if (len(args.sim_and_hardware_params) != 13):
    print("ERROR: Incorrect number of parameters in --sim_and_hardware_params")
    print("Expected: 11 parameters")
    print("Passed: ", len(args.sim_and_hardware_params), "parameters")
    sys.exit(1)
if (len(args.master_log)/7 != N_LOG):
    print("ERROR: Incorrect number of parameters in --master_log")
    print("Expected: 7*N_LOG = ",7*N_LOG, "parameters")
    print("Passed: ", len(args.master_log), "parameters")
    sys.exit(1)
if (len(args.master_hwpe)/7 != N_HWPE):
    print("ERROR: Incorrect number of parameters in --master_hwpe")
    print("Expected: 7*N_HWPE = ",7*N_HWPE, "parameters")
    print("Passed: ", len(args.master_hwpe), "parameters")
    sys.exit(1)

### GENERATE RAW TXT FILES ###
if (N_CORE <= 0):
    CORE_ZERO_FLAG = 1
    N_CORE = 1 
    filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + "master_log_0.txt"))
    os.makedirs(os.path.dirname(filepath),exist_ok=True)
    with open(filepath, 'w', encoding="ascii") as file:
        file.write('zero')
if (N_DMA <= 0):
    DMA_ZERO_FLAG = 1
    N_DMA = 1
    filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_log_{N_CORE}.txt"))
    os.makedirs(os.path.dirname(filepath),exist_ok=True)
    with open(filepath, 'w', encoding="ascii") as file:
        file.write('zero')
if (N_EXT <= 0):
    EXT_ZERO_FLAG = 1
    N_EXT = 1
    filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_log_{N_CORE+N_DMA}.txt"))
    os.makedirs(os.path.dirname(filepath),exist_ok=True)
    with open(filepath, 'w', encoding="ascii") as file:
        file.write('zero')
if (N_HWPE <= 0):
    HWPE_ZERO_FLAG = 1
    N_HWPE = 1
    filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + "master_hwpe_0.txt"))
    os.makedirs(os.path.dirname(filepath),exist_ok=True)
    with open(filepath, 'w', encoding="ascii") as file:
        file.write('zero')

N_MASTER = N_CORE + N_DMA + N_EXT + N_HWPE

next_start_id = 0
LIST_OF_FORBIDDEN_ADDRESSES_WRITE = []
LIST_OF_FORBIDDEN_ADDRESSES_READ = []

for n in range(N_MASTER): 
    if n < N_CORE:
        if CORE_ZERO_FLAG:
            continue
        else:
            filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_log_{n}.txt"))
            master = stimuli_generator(IW,WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,DATA_WIDTH,ADD_WIDTH,filepath,N_TEST_LOG,EXACT_OR_MAX_OFFSET,CYCLE_OFFSET_LOG,n,0,HWPE_WIDTH) #create the instance "master" from the class "stimuli generator"
            config, start_address, stride0, len_d0, stride1, len_d1, stride2 = getattr(args,"master_log")[n:n+7]
    elif n < N_CORE + N_DMA:
        if DMA_ZERO_FLAG:
            continue
        else:
            filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_log_{n}.txt"))
            master = stimuli_generator(IW,WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,DATA_WIDTH,ADD_WIDTH,filepath,N_TEST_LOG,EXACT_OR_MAX_OFFSET,CYCLE_OFFSET_LOG,n,0,HWPE_WIDTH) #create the instance "master" from the class "stimuli generator"
            config, start_address, stride0, len_d0, stride1, len_d1, stride2 = getattr(args,"master_log")[n:n+7]
    elif n < N_CORE + N_DMA + N_EXT:
        if EXT_ZERO_FLAG:
            continue
        else:
            filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_log_{n}.txt"))
            master = stimuli_generator(IW,WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,DATA_WIDTH,ADD_WIDTH,filepath,N_TEST_LOG,EXACT_OR_MAX_OFFSET,CYCLE_OFFSET_LOG,n,0,HWPE_WIDTH) #create the instance "master" from the class "stimuli generator"
            config, start_address, stride0, len_d0, stride1, len_d1, stride2 = getattr(args,"master_log")[n:n+7]
    else:
        if HWPE_ZERO_FLAG:
            continue
        else:
            filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_hwpe_{n-(N_MASTER-N_HWPE)}.txt"))
            master = stimuli_generator(IW,WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,HWPE_WIDTH*DATA_WIDTH,ADD_WIDTH,filepath,N_TEST_HWPE,EXACT_OR_MAX_OFFSET,CYCLE_OFFSET_HWPE,n,1,HWPE_WIDTH) # wide word for the hwpe
            config, start_address, stride0, len_d0, stride1, len_d1, stride2 = getattr(args,"master_hwpe")[n-(N_MASTER-N_HWPE):n-(N_MASTER-N_HWPE)+7]
    stride0 = int(stride0)
    len_d0 = int(len_d0)
    stride1 = int(stride1)
    len_d1 = int(len_d1)
    stride2 = int(stride2)
    match config:
        case '0':
            next_start_id = master.random_gen(next_start_id,LIST_OF_FORBIDDEN_ADDRESSES_READ,LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        case '1':
            next_start_id = master.linear_gen(stride0,start_address,next_start_id,LIST_OF_FORBIDDEN_ADDRESSES_READ,LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        case '2':
            next_start_id = master.gen_2d(stride0,len_d0,stride1,start_address,next_start_id,LIST_OF_FORBIDDEN_ADDRESSES_READ,LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
        case '3':
            next_start_id = master.gen_3d(stride0,len_d0,stride1,len_d1,stride2,start_address,next_start_id,LIST_OF_FORBIDDEN_ADDRESSES_READ,LIST_OF_FORBIDDEN_ADDRESSES_WRITE)
    
print("STEP 0 COMPLETED: created raw txt files")

### PROCESS RAW TXT FILES ###
simvector_raw_path = os.path.dirname(filepath)
simvector_processed_path = os.path.abspath(os.path.join(simvector_raw_path,"../stimuli_processed"))
process.unfold_raw_txt(simvector_raw_path,simvector_processed_path,IW,DATA_WIDTH,ADD_WIDTH,HWPE_WIDTH)
print("STEP 1 COMPLETED: unfolded txt files")

process.pad_txt_files(simvector_processed_path,IW,DATA_WIDTH,ADD_WIDTH,HWPE_WIDTH)
print("STEP 2 COMPLETED: padded txt files")
