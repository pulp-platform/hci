################################# 
#   PROCESS STIMULI TXT FILES   #
#################################
#
# This Python code provides a set of functions to easily process the raw .txt files.

import numpy as np
import os


# 1) ++UNFOLD++ the transactions in the .txt files into a cycle-level list.
# -folder_path_raw          --> String that specifies the path of the folder containing the raw txt files (where the cycle offset is still indicated)
# -folder_path_processed    --> String that specifies the path of the folder containing the new txt files created by this function
def unfold_raw_txt(folder_path_raw,folder_path_processed,IW,DATA_WIDTH,ADD_WIDTH,HWPE_WIDTH):
    file_names = [file for file in os.listdir(folder_path_raw) if file.endswith(".txt")]
    for file in file_names:
        filepath_read = os.path.join(folder_path_raw,file)
        filepath_write = os.path.join(folder_path_processed, file)
        os.makedirs(os.path.dirname(filepath_write),exist_ok=True)
        with open(filepath_read, 'r', encoding = "ascii") as file_read:
            with open(filepath_write, 'w', encoding="ascii") as file_write:
                for line in file_read:
                    if line != 'zero':
                        values = line.split()
                        id = values[0]
                        cycle_offset = values[1]               
                        wen = values[2]
                        data = values[3]
                        add = values[4]
                        if "log" in file:
                            for _ in range(int(cycle_offset)-1):
                                file_write.write("0 " + '0'*IW + " " + '0' + " " + '0'*int(DATA_WIDTH) + " " + '0'*ADD_WIDTH + "\n")
                        else:
                            for _ in range(int(cycle_offset)-1):
                                file_write.write("0 " + '0'*IW + " " + '0' + " " + '0'*int(HWPE_WIDTH*DATA_WIDTH) + " " + '0'*ADD_WIDTH + "\n")
                        file_write.write('1 ' + id + " " + wen + " " + data + " " + add + "\n")
                    else:
                        if "log" in file:
                            file_write.write("0 " + '0'*IW + " " + '0' + " " + '0'*int(DATA_WIDTH) + " " + '0'*ADD_WIDTH + "\n")
                        else:
                            file_write.write("0 " + '0'*IW + " " + '0' + " " + '0'*int(HWPE_WIDTH*DATA_WIDTH) + " " + '0'*ADD_WIDTH + "\n")


# 2) ++PAD++ txt files to have the same number of lines
# -Folder_path  --> path of the folder containing the txt files to be padded
def pad_txt_files(folder_path,IW,DATA_WIDTH,ADD_WIDTH,HWPE_WIDTH):
    file_names = [file for file in os.listdir(folder_path) if file.endswith(".txt")] # List of the txt file names in the folder
    max_lines = 0
    line_count = {} # Dictionary to store the number of lines in each txt file
    # Determining the maximum number of lines among the txt files
    for file in file_names:
        file_path = os.path.join(folder_path,file)
        with open(file_path,'r', encoding = 'ascii') as f:
            line_count[file] = sum(1 for _ in f)
            max_lines = max(max_lines, line_count[file])
    # Pad files
    for file in file_names:
        padding_needed = max_lines - line_count[file]
        if padding_needed > 0:
            file_path = os.path.join(folder_path,file)
            with open(file_path, 'a', encoding = 'ascii') as f:
                if "log" in file:
                    for _ in range(padding_needed):
                        f.write("0 " + '0'*IW + " " + '0' + " " + '0'*int(DATA_WIDTH) + " " + '0'*ADD_WIDTH + "\n") 
                else:
                    for _ in range(padding_needed):
                        f.write("0 " + '0'*IW + " " + '0' + " " + '0'*int(HWPE_WIDTH*DATA_WIDTH) + " " + '0'*ADD_WIDTH + "\n") 


                                                ###################### DEPRECATED ############################
# # 3) ++CHECK++ if during a same clock cycle two or more masters want to write to the same address
# def check_write_address(folder_path,ADD_WIDTH):
#     file_names = [file for file in os.listdir(folder_path) if file.endswith(".txt")] # List of the txt file names in the folder
#     N_MASTER = len(file_names)
#     transactions_from_all_masters = [] # List containing different lists of req, id, wen, data, add signals for each master
#     modified_masters = [0] * N_MASTER
#     for file in file_names:
#         file_path = os.path.join(folder_path,file)
#         transactions = []
#         with open(file_path, 'r', encoding = 'ascii') as f:
#             for line in f:
#                 values = line.split()
#                 transactions.append([values[0],values[1],values[2],values[3],values[4]])
#         transactions_from_all_masters.append(transactions)
#     n_cycles = len(transactions_from_all_masters[0])
#     # Check and eventually change the address
#     for i in range(n_cycles):
#         for n0 in range(1,N_MASTER):
#             for n1 in range(n0):
#                 recheck = 1
#                 while recheck: 
#                     recheck = 0
#                     check0 = int(transactions_from_all_masters[n0][i][0]) and (not int(transactions_from_all_masters[n0][i][2])) # req and (not wen)
#                     check1 = int(transactions_from_all_masters[n1][i][0]) and (not int(transactions_from_all_masters[n1][i][2]))
#                     add0 = transactions_from_all_masters[n0][i][4]
#                     add1 = transactions_from_all_masters[n1][i][4]
#                     if check0 and check1: # We check the address only if we have req = 1 and wen = 0
#                         if add0 == add1:
#                             new_add = int(transactions_from_all_masters[n0][i][4],2) + 1 # Add 1 to the integer representation of the old address
#                             max_value = 2 ** ADD_WIDTH
#                             new_add %= max_value # Modular arithmetic for overflow
#                             transactions_from_all_masters[n0][i][4] = bin(new_add)[2:].zfill(ADD_WIDTH) # Reconvert the address back into the binary representation
#                             recheck = 1 # We check again only if we changed the address
#                             modified_masters[n0] = 1
#     # Correct txt files
#     for j in range(N_MASTER):
#         if modified_masters[j]:
#             file_path = os.path.join(folder_path,file_names[j])
#             with open(file_path, 'w', encoding = 'ascii') as f:
#                 for line in range(n_cycles):
#                     req = transactions_from_all_masters[j][line][0]
#                     id = transactions_from_all_masters[j][line][1]
#                     wen = transactions_from_all_masters[j][line][2]
#                     data = transactions_from_all_masters[j][line][3]
#                     add = transactions_from_all_masters[j][line][4]
#                     f.write(str(req) + " " + str(id) + " " + str(wen) + " " + str(data) + " " + str(add) + "\n")
            

