#################################
#   STIMULI GENERATOR CLASS     # 
#################################
# 
# This file provides a detailed description of the class stimuli_generator used in the 
# main application file `masters_main.py`.
# 
# METHODS OVERVIEW:
# -random_gen: random data and RANDOM address computation
# -linear_gen: random data and LINEAR address computation

import random
import numpy as np

class stimuli_generator:
    def __init__(self,WIDTH_OF_MEMORY,N_BANKS,TOT_MEM_SIZE,DATA_WIDTH,ADD_WIDTH,filepath,N_TEST,MAX_CYCLE_OFFSET,N_MASTER):
        self.WIDTH_OF_MEMORY = WIDTH_OF_MEMORY
        self.WIDTH_OF_MEMORY_BYTE = int(WIDTH_OF_MEMORY/8)
        self.N_BANKS = N_BANKS
        self.TOT_MEM_SIZE = TOT_MEM_SIZE
        self.DATA_WIDTH = DATA_WIDTH
        self.ADD_WIDTH = int(ADD_WIDTH)
        self.filepath = filepath
        self.N_TEST = N_TEST
        self.MAX_CYCLE_OFFSET = MAX_CYCLE_OFFSET
        self.IW = int(np.ceil(np.log2(N_TEST*N_MASTER)))

    def random_data_wen_offset(self):
        data_decimal = random.randint(0, (2**(self.DATA_WIDTH))-1) # generate random data
        data = bin(data_decimal)[2:].zfill(self.DATA_WIDTH)
        wen = random.randint(0,1) # write enable signal (1 = read, 0 = write)
        cycle_offset = random.randint(1,self.MAX_CYCLE_OFFSET) # handshake request signal
        return data, wen, cycle_offset
    

    def random_gen(self,id_start,LIST_OF_FORBIDDEN_ADDRESSES):
        id = id_start
        with open(self.filepath, 'w', encoding="ascii") as file: #write an ascii file for each port of each generator
            for test in range(self.N_TEST):
                data, wen, cycle_offset = self.random_data_wen_offset()
                while True:
                    add_decimal = int((random.randint(0, int((self.TOT_MEM_SIZE*1000-self.WIDTH_OF_MEMORY_BYTE)/self.WIDTH_OF_MEMORY_BYTE)))*(self.WIDTH_OF_MEMORY_BYTE)) # generate a random word-aligned memory address.
                    if add_decimal > self.TOT_MEM_SIZE*1000-self.WIDTH_OF_MEMORY_BYTE :
                        add_decimal = add_decimal - self.TOT_MEM_SIZE*1000 #rolls over
                    add = bin(add_decimal)[2:].zfill(self.ADD_WIDTH)
                    if add not in LIST_OF_FORBIDDEN_ADDRESSES:
                        break
                if not wen:
                    LIST_OF_FORBIDDEN_ADDRESSES.append(add)
                file.write(bin(id)[2:].zfill(self.IW) + " " + str(cycle_offset) + " " + str(wen) + " " + data + " " + add + "\n")
                id = id  + 1
        return id
    
    def linear_gen(self,stride0,start_address,id_start,LIST_OF_FORBIDDEN_ADDRESSES):
        id = id_start
        with open(self.filepath, 'w', encoding="ascii") as file: #write an ascii file for each port of each generator
            next_address = int(start_address,2)
            if next_address > self.TOT_MEM_SIZE*1000-self.WIDTH_OF_MEMORY_BYTE :
                        next_address = next_address - self.TOT_MEM_SIZE*1000 #rolls over
            for test in range(self.N_TEST):
                data, wen, cycle_offset = self.random_data_wen_offset()
                while True:
                    add = bin(next_address)[2:].zfill(self.ADD_WIDTH)
                    next_address += (self.WIDTH_OF_MEMORY_BYTE)*stride0 #word-aligned memory address
                    if next_address > self.TOT_MEM_SIZE*1000-self.WIDTH_OF_MEMORY_BYTE :
                        next_address = next_address - self.TOT_MEM_SIZE*1000 #rolls over
                    if add not in LIST_OF_FORBIDDEN_ADDRESSES:
                        break
                if not wen:
                    LIST_OF_FORBIDDEN_ADDRESSES.append(add)
                file.write(bin(id)[2:].zfill(self.IW) + " " + str(cycle_offset) + " " + str(wen) + " " + data + " " + add + "\n")
                id = id + 1
                
        return id
    
    def gen_2d(self,stride0,len_d0,stride1,start_address,id_start,LIST_OF_FORBIDDEN_ADDRESSES):
        id = id_start
        with open(self.filepath, 'w', encoding="ascii") as file: #write an ascii file for each port of each generator
            start_address = int(start_address,2)
            next_address = start_address
            j = 0
            STOP = 0
            while True:
                for i in range(len_d0):
                    data, wen, cycle_offset = self.random_data_wen_offset()
                    next_address = start_address + i*(self.WIDTH_OF_MEMORY_BYTE)*stride0 + j*(self.WIDTH_OF_MEMORY_BYTE)*stride1 #word-aligned memory address
                    add = bin(next_address)[2:].zfill(self.ADD_WIDTH)
                    if next_address > self.TOT_MEM_SIZE*1000-self.WIDTH_OF_MEMORY_BYTE :
                        next_address = next_address - self.TOT_MEM_SIZE*1000 #rolls over
                    if add not in LIST_OF_FORBIDDEN_ADDRESSES:
                        if not wen:
                            LIST_OF_FORBIDDEN_ADDRESSES.append(add)
                        file.write(bin(id)[2:].zfill(self.IW) + " " + str(cycle_offset) + " " + str(wen) + " " + data + " " + add + "\n")
                        id = id + 1
                        if id - id_start >= self.N_TEST :
                            STOP = 1
                            break
                if STOP:
                    break
                j = j + 1
                
        return id
    
    def gen_3d(self,stride0,len_d0,stride1,len_d1,stride2,start_address,id_start,LIST_OF_FORBIDDEN_ADDRESSES):
        id = id_start
        with open(self.filepath, 'w', encoding="ascii") as file: #write an ascii file for each port of each generator
            start_address = int(start_address,2)
            next_address = start_address
            k = 0
            STOP = 0
            while True:
                for j in range(len_d1):
                    for i in range(len_d0):
                        data, wen, cycle_offset = self.random_data_wen_offset()
                        next_address = start_address + i*(self.WIDTH_OF_MEMORY_BYTE)*stride0 + j*(self.WIDTH_OF_MEMORY_BYTE)*stride1 + k*(self.WIDTH_OF_MEMORY_BYTE)*stride2 #word-aligned memory address
                        if next_address > self.TOT_MEM_SIZE*1000-self.WIDTH_OF_MEMORY_BYTE :
                            next_address = next_address - self.TOT_MEM_SIZE*1000 #rolls over
                        add = bin(next_address)[2:].zfill(self.ADD_WIDTH)
                        if add not in LIST_OF_FORBIDDEN_ADDRESSES:
                            if not wen:
                                LIST_OF_FORBIDDEN_ADDRESSES.append(add)
                            file.write(bin(id)[2:].zfill(self.IW) + " " + str(cycle_offset) + " " + str(wen) + " " + data + " " + add + "\n")
                            id = id + 1
                            if id - id_start >= self.N_TEST :
                                STOP = 1
                                break
                    if STOP:
                        break
                if STOP:
                        break
                k = k + 1

                
        return id

