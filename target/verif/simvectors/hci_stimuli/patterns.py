"""Access-pattern generators for StimuliGenerator.

Each method writes a cycle-accurate stimuli file directly (one line per cycle):
  req(1b) id(IWb) wen(1b) data(Nb) add(Ab)

req=0 lines are idle cycles. req=1 lines are active transactions.
There is no intermediate raw format or cycle_offset expansion step.

Patterns:
  - random:        uniformly random addresses, random read/write mix.
                   Optional: traffic_pct / traffic_read_pct for uniform idle interleaving.
  - linear:        strided 1-D scan.
                   Optional: traffic_pct / traffic_read_pct for uniform idle interleaving.
  - 2d:            strided 2-D scan (inner stride0, outer stride1).
                   Optional: idle_cycles_between_phases inserted after each outer row.
  - 3d:            strided 3-D scan (stride0, stride1, stride2).
                   Optional: idle_cycles_between_phases inserted after each mid-level block.
  - idle:          no transactions (single req=0 line).
  - matmul_phased: phased traffic modelling matrix multiply
                   (read-A phase, read-B phase, write-C phase).
                   Optional: idle_cycles_between_phases inserted between phases.

traffic_pct semantics (random, linear):
  After every transaction, emit floor((100 - traffic_pct) / traffic_pct) idle cycles.
  traffic_pct=50  => 1 idle per transaction  (req, idle, req, idle, ...)
  traffic_pct=100 => no idles (back-to-back)

traffic_read_pct semantics (random, linear):
  Fraction of transactions that are reads (wen=1); remainder are writes (wen=0).
  Only meaningful when traffic_pct < 100 or as override of the default random mix.
  When set, wen is no longer random: the first n_reads transactions are reads,
  the rest are writes (pattern: all reads first, then all writes).

idle_cycles_between_phases semantics (2d, 3d, matmul_phased):
  Number of req=0 cycles inserted at each phase boundary (between outer rows for
  2d/3d, between read-A/read-B/write-C for matmul_phased). Models compute time
  between bursts of memory accesses.

All patterns respect the cross-master forbidden address lists:
  - forbidden_write: addresses already read -> no later master may write here
  - forbidden_read:  addresses already written -> no later master may read/write here
"""

import random


class PatternsMixin:
    """Mixin providing memory access pattern generators."""

    # ------------------------------------------------------------------ #
    # Shared helpers                                                       #
    # ------------------------------------------------------------------ #

    @staticmethod
    def _parse_address(addr_str):
        """Parse a binary, hex (0x...), or decimal string to int."""
        s = str(addr_str)
        if s.startswith('0x') or s.startswith('0X'):
            return int(s, 16)
        if set(s) <= {'0', '1'}:
            return int(s, 2)
        return int(s, 0)

    @staticmethod
    def _align_down(value, alignment):
        if alignment <= 0:
            return value
        return (value // alignment) * alignment

    @staticmethod
    def _phase_counts(total_ops, ratio_a, ratio_b, ratio_c):
        """Split total_ops into three phases according to ratios."""
        ra = max(0, int(ratio_a))
        rb = max(0, int(ratio_b))
        rc = max(0, int(ratio_c))
        if ra == 0 and rb == 0 and rc == 0:
            ra, rb, rc = 1, 1, 1
        rsum = ra + rb + rc
        cnt_a = (total_ops * ra) // rsum
        cnt_b = (total_ops * rb) // rsum
        cnt_c = total_ops - cnt_a - cnt_b

        if total_ops >= 3:
            if ra > 0 and cnt_a == 0:
                cnt_a = 1
                cnt_c = max(0, cnt_c - 1)
            if rb > 0 and cnt_b == 0:
                cnt_b = 1
                cnt_c = max(0, cnt_c - 1)
            if rc > 0 and cnt_c == 0:
                if cnt_a > 1:
                    cnt_a -= 1
                    cnt_c = 1
                elif cnt_b > 1:
                    cnt_b -= 1
                    cnt_c = 1
        return cnt_a, cnt_b, cnt_c

    @staticmethod
    def _idles_per_req(traffic_pct):
        """Number of idle cycles to emit after each transaction for a given traffic_pct."""
        traffic_pct = max(1, min(100, int(traffic_pct)))
        if traffic_pct >= 100:
            return 0
        return int(round((100 - traffic_pct) / traffic_pct))

    def _is_allowed(self, add, wen, forbidden_read, forbidden_write):
        """Return True if the address is not in the relevant forbidden list."""
        return add not in (forbidden_read if wen else forbidden_write)

    def _record_access(self, add, wen, forbidden_read_new, forbidden_write_new):
        """Mark add as used by this master."""
        forbidden_write_new.append(add)
        if not wen:
            forbidden_read_new.append(add)

    # ------------------------------------------------------------------ #
    # Access patterns                                                      #
    # ------------------------------------------------------------------ #

    def random_gen(
        self,
        id_start,
        forbidden_read,
        forbidden_write,
        region_base=0,
        region_size=None,
        traffic_pct=100,
        traffic_read_pct=None,
    ):
        """Uniformly random addresses within [region_base, region_base + region_size).

        traffic_pct: bus utilisation percentage. After each transaction,
          floor((100 - traffic_pct) / traffic_pct) idle cycles are emitted.
          Default 100 = back-to-back (no idles).

        traffic_read_pct: if set, the first n_reads transactions are reads and
          the rest are writes. If not set, wen is random per transaction.
        """
        total_mem_bytes = int(self.TOT_MEM_SIZE * 1024)
        if region_size is None:
            region_size = total_mem_bytes
        region_size = min(region_size, total_mem_bytes - region_base)
        n_words = max(1, region_size // self.WIDTH_OF_MEMORY_BYTE)
        n_idles = self._idles_per_req(traffic_pct)

        # Build wen sequence
        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1] * n_reads + [0] * (self.N_TEST - n_reads)
        else:
            wen_seq = None

        id_value = id_start
        forbidden_read_new = []
        forbidden_write_new = []
        with open(self.filepath, "w", encoding="ascii") as file:
            for i in range(self.N_TEST):
                if wen_seq is not None:
                    wen = wen_seq[i]
                    data = "0" * self.DATA_WIDTH if wen else self.random_data()
                else:
                    data, wen = self.data_wen()
                while True:
                    add_decimal = region_base + random.randint(0, int(n_words) - 1) * self.WIDTH_OF_MEMORY_BYTE
                    add = bin(int(add_decimal))[2:].zfill(self.ADD_WIDTH)
                    if self._is_allowed(add, wen, forbidden_read, forbidden_write):
                        self._record_access(add, wen, forbidden_read_new, forbidden_write_new)
                        break
                self._write_req(file, id_value, wen, data, add)
                id_value += 1
                for _ in range(n_idles):
                    self._write_idle(file)
        forbidden_read.extend(forbidden_read_new)
        forbidden_write.extend(forbidden_write_new)
        return id_value

    def linear_gen(
        self,
        stride0,
        start_address,
        id_start,
        forbidden_read,
        forbidden_write,
        traffic_pct=100,
        traffic_read_pct=None,
    ):
        """Strided 1-D linear scan. Forbidden addresses are skipped (no idle inserted).

        traffic_pct / traffic_read_pct: see random_gen.
        """
        n_idles = self._idles_per_req(traffic_pct)

        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1] * n_reads + [0] * (self.N_TEST - n_reads)
        else:
            wen_seq = None

        id_value = id_start
        forbidden_read_new = []
        forbidden_write_new = []
        seq_idx = 0
        with open(self.filepath, "w", encoding="ascii") as file:
            next_address = self._parse_address(start_address)
            if next_address > self.TOT_MEM_SIZE * 1024 - self.WIDTH_OF_MEMORY_BYTE:
                next_address -= self.TOT_MEM_SIZE * 1024
            for i in range(self.N_TEST):
                if wen_seq is not None:
                    wen = wen_seq[i]
                    data = "0" * self.DATA_WIDTH if wen else self.random_data()
                else:
                    data, wen = self.data_wen()
                add = bin(next_address)[2:].zfill(self.ADD_WIDTH)
                next_address += self.WIDTH_OF_MEMORY_BYTE * stride0
                if next_address > self.TOT_MEM_SIZE * 1024 - self.WIDTH_OF_MEMORY_BYTE:
                    next_address -= self.TOT_MEM_SIZE * 1024
                if not self._is_allowed(add, wen, forbidden_read, forbidden_write):
                    continue
                self._record_access(add, wen, forbidden_read_new, forbidden_write_new)
                self._write_req(file, id_value, wen, data, add)
                id_value += 1
                for _ in range(n_idles):
                    self._write_idle(file)
        forbidden_read.extend(forbidden_read_new)
        forbidden_write.extend(forbidden_write_new)
        return id_value

    def gen_2d(
        self,
        stride0,
        len_d0,
        stride1,
        start_address,
        id_start,
        forbidden_read,
        forbidden_write,
        idle_cycles_between_phases=0,
    ):
        """Strided 2-D scan: inner loop stride0/len_d0, outer loop stride1.

        idle_cycles_between_phases: req=0 cycles inserted after each completed inner row.
        """
        id_value = id_start
        forbidden_read_new = []
        forbidden_write_new = []
        with open(self.filepath, "w", encoding="ascii") as file:
            start_address_int = self._parse_address(start_address)
            j = 0
            while id_value - id_start < self.N_TEST:
                for i in range(len_d0):
                    data, wen = self.data_wen()
                    next_address = (
                        start_address_int
                        + i * self.WIDTH_OF_MEMORY_BYTE * stride0
                        + j * self.WIDTH_OF_MEMORY_BYTE * stride1
                    )
                    if next_address > self.TOT_MEM_SIZE * 1024 - self.WIDTH_OF_MEMORY_BYTE:
                        next_address -= self.TOT_MEM_SIZE * 1024
                    add = bin(next_address)[2:].zfill(self.ADD_WIDTH)
                    if not self._is_allowed(add, wen, forbidden_read, forbidden_write):
                        continue
                    self._record_access(add, wen, forbidden_read_new, forbidden_write_new)
                    self._write_req(file, id_value, wen, data, add)
                    id_value += 1
                    if id_value - id_start >= self.N_TEST:
                        break
                for _ in range(idle_cycles_between_phases):
                    self._write_idle(file)
                j += 1
        forbidden_read.extend(forbidden_read_new)
        forbidden_write.extend(forbidden_write_new)
        return id_value

    def gen_3d(
        self,
        stride0,
        len_d0,
        stride1,
        len_d1,
        stride2,
        start_address,
        id_start,
        forbidden_read,
        forbidden_write,
        idle_cycles_between_phases=0,
    ):
        """Strided 3-D scan: inner stride0/len_d0, mid stride1/len_d1, outer stride2.

        idle_cycles_between_phases: req=0 cycles inserted after each completed mid-level block.
        """
        id_value = id_start
        forbidden_read_new = []
        forbidden_write_new = []
        with open(self.filepath, "w", encoding="ascii") as file:
            start_address_int = self._parse_address(start_address)
            k = 0
            while id_value - id_start < self.N_TEST:
                for j in range(len_d1):
                    for i in range(len_d0):
                        data, wen = self.data_wen()
                        next_address = (
                            start_address_int
                            + i * self.WIDTH_OF_MEMORY_BYTE * stride0
                            + j * self.WIDTH_OF_MEMORY_BYTE * stride1
                            + k * self.WIDTH_OF_MEMORY_BYTE * stride2
                        )
                        if next_address > self.TOT_MEM_SIZE * 1024 - self.WIDTH_OF_MEMORY_BYTE:
                            next_address -= self.TOT_MEM_SIZE * 1024
                        add = bin(next_address)[2:].zfill(self.ADD_WIDTH)
                        if not self._is_allowed(add, wen, forbidden_read, forbidden_write):
                            continue
                        self._record_access(add, wen, forbidden_read_new, forbidden_write_new)
                        self._write_req(file, id_value, wen, data, add)
                        id_value += 1
                        if id_value - id_start >= self.N_TEST:
                            break
                    if id_value - id_start >= self.N_TEST:
                        break
                    for _ in range(idle_cycles_between_phases):
                        self._write_idle(file)
                k += 1
        forbidden_read.extend(forbidden_read_new)
        forbidden_write.extend(forbidden_write_new)
        return id_value

    def idle_gen(self, id_start):
        """Emit a single req=0 idle line (master never issues transactions)."""
        with open(self.filepath, "w", encoding="ascii") as file:
            self._write_idle(file)
        return id_start

    def matmul_phased_gen(
        self,
        id_start,
        forbidden_read,
        forbidden_write,
        region_base_address,
        region_size_bytes,
        matmul_ratio_a=1,
        matmul_ratio_b=1,
        matmul_ratio_c=1,
        idle_cycles_between_phases=0,
        region_base_address_a=None,
        region_size_bytes_a=None,
        region_base_address_b=None,
        region_size_bytes_b=None,
        region_base_address_c=None,
        region_size_bytes_c=None,
    ):
        """Phased traffic modelling matrix multiply: read-A, read-B, write-C.

        Each phase reads/writes its own sub-region. If region_base_address_a/b/c
        and region_size_bytes_a/b/c are provided, they are used directly for each
        phase. Otherwise the combined region [region_base_address, +region_size_bytes)
        is split into equal thirds automatically.

        idle_cycles_between_phases: req=0 cycles inserted between each pair of
          active phases (after read-A and after read-B, if those phases are non-empty).
          Models computation time between memory bursts.
        """
        id_value = id_start
        forbidden_read_new = []
        forbidden_write_new = []
        access_bytes = max(1, self.DATA_WIDTH // 8)
        total_mem_bytes = int(self.TOT_MEM_SIZE * 1024)

        def _resolve_region(base_override, size_override, fallback_base, fallback_size):
            if base_override is not None and size_override is not None:
                b = self._align_down(int(base_override), access_bytes)
                s = self._align_down(int(size_override), access_bytes)
            else:
                b = self._align_down(int(fallback_base), access_bytes)
                s = self._align_down(int(fallback_size), access_bytes)
            if b + s > total_mem_bytes:
                s = self._align_down(total_mem_bytes - b, access_bytes)
            return b, s

        # If per-phase regions are explicitly provided, use them directly
        if region_base_address_a is not None and region_size_bytes_a is not None:
            a_base, a_size = _resolve_region(region_base_address_a, region_size_bytes_a, 0, 0)
            b_base, b_size = _resolve_region(region_base_address_b, region_size_bytes_b, a_base, a_size)
            c_base, c_size = _resolve_region(region_base_address_c, region_size_bytes_c, a_base, a_size)
        else:
            # Auto-split combined region into thirds
            base = self._align_down(int(region_base_address), access_bytes)
            size = self._align_down(int(region_size_bytes), access_bytes)
            if base + size > total_mem_bytes:
                size = self._align_down(total_mem_bytes - base, access_bytes)
            region_words = size // access_bytes
            if region_words < 3:
                with open(self.filepath, "w", encoding="ascii") as file:
                    self._write_idle(file)
                return id_value
            a_words = max(1, region_words // 3)
            b_words = max(1, region_words // 3)
            c_words = region_words - a_words - b_words
            a_base = base;            a_size = a_words * access_bytes
            b_base = a_base + a_size; b_size = b_words * access_bytes
            c_base = b_base + b_size; c_size = c_words * access_bytes

        a_end = a_base + a_size
        b_end = b_base + b_size
        c_end = c_base + c_size

        cnt_a, cnt_b, cnt_c = self._phase_counts(
            self.N_TEST,
            int(matmul_ratio_a),
            int(matmul_ratio_b),
            int(matmul_ratio_c),
        )

        def _emit_phase(file_obj, count, wen, phase_base, phase_end):
            nonlocal id_value
            addr = phase_base
            for _ in range(count):
                data = "0" * self.DATA_WIDTH if wen else self.random_data()
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                self._write_req(file_obj, id_value, wen, data, add)
                self._record_access(add, wen, forbidden_read_new, forbidden_write_new)
                id_value += 1
                addr += access_bytes
                if addr >= phase_end:
                    addr = phase_base

        with open(self.filepath, "w", encoding="ascii") as file:
            _emit_phase(file, cnt_a, 1, a_base, a_end)           # read A
            if cnt_a > 0 and (cnt_b > 0 or cnt_c > 0):
                for _ in range(idle_cycles_between_phases):
                    self._write_idle(file)
            _emit_phase(file, cnt_b, 1, b_base, b_end)           # read B
            if cnt_b > 0 and cnt_c > 0:
                for _ in range(idle_cycles_between_phases):
                    self._write_idle(file)
            _emit_phase(file, cnt_c, 0, c_base, c_end)           # write C

        forbidden_read.extend(forbidden_read_new)
        forbidden_write.extend(forbidden_write_new)
        return id_value
