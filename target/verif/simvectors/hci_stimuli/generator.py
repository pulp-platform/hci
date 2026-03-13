"""StimuliGenerator: infrastructure for writing cycle-accurate stimuli files.

Each output file has one line per simulation cycle in the format:
  req(1b) id(IWb) wen(1b) be(BEWb) data(Nb) add(Ab)

where BEW = DATA_WIDTH / 8 (one bit per byte lane).

req=0 means no transaction that cycle (id/wen/be/data/add are don't-cares).
req=1 means an active transaction.
be is all-ones for full-width transactions. For a trailing beat that covers only
  T bytes of a DATA_WIDTH/8-byte word, be has bits [T-1:0] set and the rest zero.
  For reads (wen=1) be is still driven (all-ones for full, partial for trailing)
  for documentation/tracing purposes; the memory subsystem typically ignores be on
  reads.
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

    @property
    def BE_WIDTH(self):
        """Byte-enable width: one bit per byte lane of DATA_WIDTH."""
        return max(1, self.DATA_WIDTH // 8)

    def _full_be(self):
        """All-ones byte-enable string (all lanes active)."""
        return "1" * self.BE_WIDTH

    def _partial_be(self, valid_bytes):
        """Byte-enable string with bits [valid_bytes-1:0] set, rest zero.

        valid_bytes must be in [1, BE_WIDTH]. Used for the trailing beat of a
        transfer whose total size is not a multiple of the bus width.
        """
        valid_bytes = max(1, min(int(valid_bytes), self.BE_WIDTH))
        return ("0" * (self.BE_WIDTH - valid_bytes)) + ("1" * valid_bytes)

    def _format_id(self, id_value):
        return bin(id_value % (1 << self.IW))[2:].zfill(self.IW)

    def random_data(self):
        data_decimal = random.randint(0, (2 ** self.DATA_WIDTH) - 1)
        return bin(data_decimal)[2:].zfill(self.DATA_WIDTH)

    def _write_req(self, file_obj, id_value, wen, data, add, be=None):
        """Write one active-request line (req=1).

        be: binary string of BE_WIDTH bits. Defaults to all-ones (full beat).
        """
        if be is None:
            be = self._full_be()
        file_obj.write(
            "1 "
            + self._format_id(id_value)
            + " "
            + str(wen)
            + " "
            + be
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
            + "0" * self.BE_WIDTH
            + " "
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
