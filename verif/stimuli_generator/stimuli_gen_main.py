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
# After setting the correct parameters in the files hci_params.py and sim_params.py, you can run the 
# command 'python masters_main.py', specifying the necessary arguments.
# Each argument represent a master's memory access type (0 random, 1 linear)
# The last argument you provide is for the HWPE, while the others represents the masters from the log branch of the HCI
#
# EXAMPLE:
#
# python stimuli_gen_main.py 0 1 1 0
#
# This command will generate several different .txt files that will be used in a verification suite with three masters in the logarithmic branch and one HWPE.
# In particular for the logarithmic branch:
# - First master: random access
# - Second master: linear access
# - Third master: linear access
# For the HWPE:
# - HWPE: random access

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
import hci_params
import sim_params
# N_MASTER = parameters.N_MASTER
N_BANKS = hci_params.N_BANKS
TOT_MEM_SIZE = hci_params.TOT_MEM_SIZE
WIDTH_OF_MEMORY = hci_params.WIDTH_OF_MEMORY
N_CORE = hci_params.N_CORE
N_DMA = hci_params.N_DMA
N_EXT = hci_params.N_EXT
N_HWPE = hci_params.N_HWPE
WIDTH_OF_MEMORY_BYTE = WIDTH_OF_MEMORY/8
N_WORDS = (TOT_MEM_SIZE*1000/N_BANKS)/WIDTH_OF_MEMORY_BYTE
if (not N_WORDS.is_integer()): #check if the number of words is an integer value
    print("ERROR: the number of words is not an integer value")
    sys.exit(1)

ADD_WIDTH = int(np.ceil(np.log2(TOT_MEM_SIZE*1000))) # Each memory address point to a byte
DATA_WIDTH = WIDTH_OF_MEMORY

N_TEST = sim_params.N_TEST
MAX_CYCLE_OFFSET = sim_params.MAX_CYCLE_OFFSET
N_MASTER = N_CORE + N_DMA + N_EXT + N_HWPE
IW = int(np.ceil(np.log2(N_TEST*N_MASTER)))
#argpasre
import argparse 

parser = argparse.ArgumentParser(description="This script generates .txt files containing stimuli for use in the HCI verification suite.\n\n"
                                 "USAGE EXAMPLE:\n"
                                 "python stimuli_gen_main.py --master_log0 0, --master_log1 1 0101001 2 --master_hwpe0 2 1001010 3 10 2",
                                 formatter_class=argparse.RawTextHelpFormatter,)

for i in range(N_MASTER-N_HWPE):
    parser.add_argument(f'--master_log{i}', nargs='+', default=[], required=True, help=f"Specify the parameters for memory access related to master_log{i}:\n"
                                                                                        "   - Memory access type: 0 (random), 1 (linear), 2 (2D), 3 (3D) \n"
                                                                                        "   - Starting address in binary (required for linear, 2D, and 3D accesses)\n"
                                                                                        "   - Stride0 (required for linear, 2D, and 3D accesses)\n"
                                                                                        "   - Len_d0 (required for 2D and 3D accesses)\n"
                                                                                        "   - Stride1 (required for 2D and 3D accesses)\n"
                                                                                        "   - Len_d1 (required for 3D accesses)\n"
                                                                                        "   - Stride2 (required for 3D accesses)\n\n"
                                                                                        "NOTE: There is no need to specify the \"outer\" length for linear, 2D, and 3D accesses,\n"
                                                                                        "as the program will automatically stop once the specified `N_TEST` vectors are reached.")
for j in range(N_HWPE):
    parser.add_argument(f'--master_hwpe{j}', nargs='+', default=[], required=True, help=f"Specify the parameters for memory access related to master_hwpe{i}:\n"
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
#end argparse

#generate the txt files containing the stimuli for the testbench
next_start_id = 0
LIST_OF_FORBIDDEN_ADDRESSES = []
for n in range(N_MASTER): 
    if n < N_MASTER-N_HWPE:
        master_name = f'master_log{n}'
        filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_log_{n}.txt"))
        master = stimuli_generator(WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,DATA_WIDTH,ADD_WIDTH,filepath,N_TEST,MAX_CYCLE_OFFSET,N_MASTER) #create the instance "master" from the class "stimuli generator"
    else:
        master_name = f'master_hwpe{n-(N_MASTER-N_HWPE)}'
        filepath = os.path.abspath(os.path.join(code_directory, "../../verif/simvectors/stimuli_raw/" + f"master_hwpe_{n-(N_MASTER-N_HWPE)}.txt"))
        master = stimuli_generator(WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,4*DATA_WIDTH,ADD_WIDTH,filepath,N_TEST,MAX_CYCLE_OFFSET,N_MASTER) # wide word for the hwpe
    
    config, start_address, stride0, len_d0, stride1, len_d1, stride2 = (getattr(args,master_name, None) + [0] * 7)[:7]
    stride0 = int(stride0)
    len_d0 = int(len_d0)
    stride1 = int(stride1)
    len_d1 = int(len_d1)
    stride2 = int(stride2)
    match config:
        case '0':
            next_start_id = master.random_gen(next_start_id,LIST_OF_FORBIDDEN_ADDRESSES)
        case '1':
            next_start_id = master.linear_gen(stride0,start_address,next_start_id,LIST_OF_FORBIDDEN_ADDRESSES)
        case '2':
            next_start_id = master.gen_2d(stride0,len_d0,stride1,start_address,next_start_id,LIST_OF_FORBIDDEN_ADDRESSES)
        case '3':
            next_start_id = master.gen_3d(stride0,len_d0,stride1,len_d1,stride2,start_address,next_start_id,LIST_OF_FORBIDDEN_ADDRESSES)
    
print("STEP 0 COMPLETED: created raw txt files")
simvector_raw_path = os.path.dirname(filepath)
simvector_processed_path = os.path.abspath(os.path.join(simvector_raw_path,"../stimuli_processed"))
process.unfold_raw_txt(simvector_raw_path,simvector_processed_path,IW,DATA_WIDTH,ADD_WIDTH)
print("STEP 1 COMPLETED: unfolded txt files")
#process.pad_txt_files(simvector_processed_path,IW,DATA_WIDTH,ADD_WIDTH)
#print("STEP 2 COMPLETED: padded txt files")
#process.check_write_address(simvector_processed_path,ADD_WIDTH)
#print("STEP 3 COMPLETED: checked txt files")
#print("FINISHED! Stimuli ready to be used")