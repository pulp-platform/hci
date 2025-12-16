"""Processor helpers: unfold and pad stimuli text files."""

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
