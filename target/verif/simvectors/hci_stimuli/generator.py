"""StimuliGenerator: infrastructure for writing cycle-accurate stimuli files.

Each output file has one line per simulation cycle in the format:
  req(1b) id(IWb) wen(1b) data(Nb) add(Ab)

req=0 means no transaction that cycle (id/wen/data/add are don't-cares).
req=1 means an active transaction.
"""

import os
import random

from .patterns import PatternsMixin


class StimuliGenerator(PatternsMixin):
    def __init__(
        self,
        IW,
        WIDTH_OF_MEMORY,
        N_BANKS,
        TOT_MEM_SIZE,
        DATA_WIDTH,
        ADD_WIDTH,
        filepath,
        N_TEST,
        MASTER_NUMBER_IDENTIFICATION,
    ):
        self.WIDTH_OF_MEMORY = WIDTH_OF_MEMORY
        self.WIDTH_OF_MEMORY_BYTE = int(WIDTH_OF_MEMORY / 8)
        self.N_BANKS = N_BANKS
        self.TOT_MEM_SIZE = TOT_MEM_SIZE
        self.DATA_WIDTH = DATA_WIDTH
        self.ADD_WIDTH = int(ADD_WIDTH)
        self.filepath = filepath
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        self.N_TEST = N_TEST
        self.IW = IW
        self.MASTER_NUMBER_IDENTIFICATION = MASTER_NUMBER_IDENTIFICATION

    def _format_id(self, id_value):
        return bin(id_value % (1 << self.IW))[2:].zfill(self.IW)

    def random_data(self):
        data_decimal = random.randint(0, (2 ** self.DATA_WIDTH) - 1)
        return bin(data_decimal)[2:].zfill(self.DATA_WIDTH)

    def _write_req(self, file_obj, id_value, wen, data, add):
        """Write one active-request line (req=1)."""
        file_obj.write(
            "1 "
            + self._format_id(id_value)
            + " "
            + str(wen)
            + " "
            + data
            + " "
            + add
            + "\n"
        )

    def _write_idle(self, file_obj):
        """Write one idle line (req=0)."""
        file_obj.write(
            "0 "
            + "0" * self.IW
            + " 0 "
            + "0" * self.DATA_WIDTH
            + " "
            + "0" * self.ADD_WIDTH
            + "\n"
        )

    def _write_pause(self, file_obj):
        """Write a PAUSE fence token line."""
        file_obj.write("PAUSE\n")

    def data_wen(self):
        wen = random.randint(0, 1)  # 1=read, 0=write
        if wen:
            data = "0" * self.DATA_WIDTH
        else:
            data = self.random_data()
        return data, wen
