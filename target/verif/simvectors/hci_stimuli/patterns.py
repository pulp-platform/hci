"""Access-pattern generators for StimuliGenerator.

Each method writes a cycle-accurate stimuli file directly (one line per cycle):
  req(1b) id(IWb) wen(1b) data(Nb) add(Ab)

req=0 lines are idle cycles. req=1 lines are active transactions.

Fence semantics (one trailing PAUSE per pattern):
  Each pattern ends with a PAUSE. fence_idx[i] increments when resume_i fires while
  fence_reached_o is high (i.e. while the driver is sitting at the PAUSE).
  fence_idx[i] >= k means driver i has been granted to leave fence k-1,
  i.e. pattern k-1 is complete and driver i is about to start pattern k.

  resume_i fires when the dependencies of the NEXT pattern are satisfied.
  So resume_i = "your next job's inputs are ready, proceed".

  Trailing PAUSE of the last pattern has mask=0 → resume_i fires in one cycle
  → fence_idx advances to N_patterns, signalling final completion to dependents.

All generators accept append=True to open the file in append mode.
"""

import random

class PatternsMixin:

    @staticmethod
    def _parse_address(addr_str):
        s = str(addr_str)
        if s.startswith('0x') or s.startswith('0X'): return int(s, 16)
        if set(s) <= {'0', '1'}: return int(s, 2)
        return int(s, 0)

    @staticmethod
    def _align_down(value, alignment):
        if alignment <= 0: return value
        return (value // alignment) * alignment

    @staticmethod
    def _phase_counts(total_ops, ratio_a, ratio_b, ratio_c):
        ra = max(0, int(ratio_a)); rb = max(0, int(ratio_b)); rc = max(0, int(ratio_c))
        if ra == 0 and rb == 0 and rc == 0: ra, rb, rc = 1, 1, 1
        s = ra + rb + rc
        ca = (total_ops * ra) // s; cb = (total_ops * rb) // s; cc = total_ops - ca - cb
        if total_ops >= 3:
            if ra > 0 and ca == 0: ca = 1; cc = max(0, cc-1)
            if rb > 0 and cb == 0: cb = 1; cc = max(0, cc-1)
            if rc > 0 and cc == 0:
                if ca > 1: ca -= 1; cc = 1
                elif cb > 1: cb -= 1; cc = 1
        return ca, cb, cc

    @staticmethod
    def _idles_per_req(traffic_pct):
        traffic_pct = max(1, min(100, int(traffic_pct)))
        return 0 if traffic_pct >= 100 else int(round((100 - traffic_pct) / traffic_pct))

    def _is_allowed(self, add, wen, read_blocked_set, write_blocked_set):
        return add not in (read_blocked_set if wen else write_blocked_set)

    def _record_access(self, add, wen, read_blocked_set, write_blocked_set):
        write_blocked_set.add(add)
        if not wen:
            read_blocked_set.add(add)

    @staticmethod
    def _init_blocked_sets(read_blocked, write_blocked):
        return set(read_blocked or []), set(write_blocked or [])

    @staticmethod
    def _extend_unique_sorted(target, values):
        if not isinstance(target, list):
            return
        known = set(target)
        for v in sorted(values):
            if v in known:
                continue
            target.append(v)
            known.add(v)

    def _commit_blocked_sets(self, read_blocked, write_blocked, read_blocked_set, write_blocked_set):
        self._extend_unique_sorted(read_blocked, read_blocked_set)
        self._extend_unique_sorted(write_blocked, write_blocked_set)

    def _require_exact_emits(self, pattern_name, id_start, id_value):
        emitted = int(id_value - id_start)
        expected = int(self.N_TEST)
        if emitted == expected:
            return
        raise RuntimeError(
            f"{pattern_name}: emitted {emitted} transaction(s), expected {expected}. "
            "Adjust region/shape/traffic to satisfy the read/write blocked policy."
        )

    def _open(self, append):
        return open(self.filepath, "a" if append else "w", encoding="ascii")

    def _total_mem_bytes(self):
        return int(self.TOT_MEM_SIZE * 1024)

    def _normalize_addr(self, addr):
        total = self._total_mem_bytes()
        if total <= self.WIDTH_OF_MEMORY_BYTE:
            return 0
        max_addr = total - self.WIDTH_OF_MEMORY_BYTE
        a = int(addr) % total
        if a > max_addr:
            a = max_addr
        return a

    @staticmethod
    def _parse_read_write_schedule(schedule, default="4read_1write"):
        raw = str(schedule if schedule is not None else default).strip().lower()
        if not raw:
            raw = default
        tokens = []
        for chunk in raw.replace("-", "_").split("_"):
            c = chunk.strip()
            if not c:
                continue
            count = 1
            word = c
            if c[0].isdigit():
                i = 0
                while i < len(c) and c[i].isdigit():
                    i += 1
                count = max(1, int(c[:i]))
                word = c[i:]
            elif c[-1].isdigit():
                i = len(c) - 1
                while i >= 0 and c[i].isdigit():
                    i -= 1
                count = max(1, int(c[i + 1:]))
                word = c[:i + 1]
            word = word.strip()
            if word in {"read", "r"}:
                tokens.extend(["R"] * count)
            elif word in {"write", "w"}:
                tokens.extend(["W"] * count)
        if not tokens:
            return ["R", "R", "R", "R", "W"]
        return tokens

    @staticmethod
    def _parse_abc_schedule(schedule, default="A_B_C"):
        raw = str(schedule if schedule is not None else default).strip().upper()
        if not raw:
            raw = default
        tokens = []
        for chunk in raw.replace("-", "_").split("_"):
            c = chunk.strip()
            if not c:
                continue
            count = 1
            letter = c
            if c[0].isdigit():
                i = 0
                while i < len(c) and c[i].isdigit():
                    i += 1
                count = max(1, int(c[:i]))
                letter = c[i:]
            elif c[-1].isdigit():
                i = len(c) - 1
                while i >= 0 and c[i].isdigit():
                    i -= 1
                count = max(1, int(c[i + 1:]))
                letter = c[:i + 1]
            letter = letter.strip().upper()
            if letter in {"A", "B", "C"}:
                tokens.extend([letter] * count)
        if not tokens:
            return ["A", "B", "C"]
        return tokens

    # ------------------------------------------------------------------ #
    # Access patterns — each writes: transactions | PAUSE                 #
    # ------------------------------------------------------------------ #

    def random_gen(self, id_start, read_blocked, write_blocked,
                   region_base=0, region_size=None, traffic_pct=100,
                   traffic_read_pct=None, append=False):
        total = int(self.TOT_MEM_SIZE * 1024)
        if region_size is None: region_size = total
        region_size = min(region_size, total - region_base)
        n_words = max(1, region_size // self.WIDTH_OF_MEMORY_BYTE)
        n_idles = self._idles_per_req(traffic_pct)
        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1]*n_reads + [0]*(self.N_TEST-n_reads)
        else:
            wen_seq = None
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        max_attempts = max(1, n_words * 4)
        with self._open(append) as f:
            for i in range(self.N_TEST):
                wen = wen_seq[i] if wen_seq is not None else None
                if wen is None: data, wen = self.data_wen()
                else: data = "0"*self.DATA_WIDTH if wen else self.random_data()
                placed = False
                for _ in range(max_attempts):
                    ad = region_base + random.randint(0, int(n_words)-1)*self.WIDTH_OF_MEMORY_BYTE
                    add = bin(int(ad))[2:].zfill(self.ADD_WIDTH)
                    if self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                        self._record_access(add, wen, read_blocked_set, write_blocked_set)
                        placed = True
                        break
                if not placed:
                    continue
                self._write_req(f, id_value, wen, data, add); id_value += 1
                for _ in range(n_idles): self._write_idle(f)
            self._write_pause(f)
        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("random", id_start, id_value)
        return id_value

    def linear_gen(self, stride0, start_address, id_start, read_blocked, write_blocked,
                   traffic_pct=100, traffic_read_pct=None, append=False):
        n_idles = self._idles_per_req(traffic_pct)
        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1]*n_reads + [0]*(self.N_TEST-n_reads)
        else:
            wen_seq = None
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        with self._open(append) as f:
            addr = self._parse_address(start_address)
            if addr > self.TOT_MEM_SIZE*1024 - self.WIDTH_OF_MEMORY_BYTE:
                addr -= self.TOT_MEM_SIZE*1024
            for i in range(self.N_TEST):
                wen = wen_seq[i] if wen_seq is not None else None
                if wen is None: data, wen = self.data_wen()
                else: data = "0"*self.DATA_WIDTH if wen else self.random_data()
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                addr += self.WIDTH_OF_MEMORY_BYTE * stride0
                if addr > self.TOT_MEM_SIZE*1024 - self.WIDTH_OF_MEMORY_BYTE:
                    addr -= self.TOT_MEM_SIZE*1024
                if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set): continue
                self._record_access(add, wen, read_blocked_set, write_blocked_set)
                self._write_req(f, id_value, wen, data, add); id_value += 1
                for _ in range(n_idles): self._write_idle(f)
            self._write_pause(f)
        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("linear", id_start, id_value)
        return id_value

    def gen_2d(self, stride0, len_d0, stride1, start_address, id_start,
               read_blocked, write_blocked, idle_cycles_between_phases=0, append=False):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        with self._open(append) as f:
            base = self._parse_address(start_address); j = 0
            while id_value - id_start < self.N_TEST:
                emitted_before = id_value
                for i in range(len_d0):
                    data, wen = self.data_wen()
                    addr = base + i*self.WIDTH_OF_MEMORY_BYTE*stride0 + j*self.WIDTH_OF_MEMORY_BYTE*stride1
                    if addr > self.TOT_MEM_SIZE*1024 - self.WIDTH_OF_MEMORY_BYTE:
                        addr -= self.TOT_MEM_SIZE*1024
                    add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                    if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set): continue
                    self._record_access(add, wen, read_blocked_set, write_blocked_set)
                    self._write_req(f, id_value, wen, data, add); id_value += 1
                    if id_value - id_start >= self.N_TEST: break
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
                if id_value == emitted_before:
                    break
                j += 1
            self._write_pause(f)
        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("2d", id_start, id_value)
        return id_value

    def gen_3d(self, stride0, len_d0, stride1, len_d1, stride2, start_address, id_start,
               read_blocked, write_blocked, idle_cycles_between_phases=0, append=False):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        with self._open(append) as f:
            base = self._parse_address(start_address); k = 0
            while id_value - id_start < self.N_TEST:
                emitted_before = id_value
                for j in range(len_d1):
                    for i in range(len_d0):
                        data, wen = self.data_wen()
                        addr = base + i*self.WIDTH_OF_MEMORY_BYTE*stride0 + j*self.WIDTH_OF_MEMORY_BYTE*stride1 + k*self.WIDTH_OF_MEMORY_BYTE*stride2
                        if addr > self.TOT_MEM_SIZE*1024 - self.WIDTH_OF_MEMORY_BYTE:
                            addr -= self.TOT_MEM_SIZE*1024
                        add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                        if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set): continue
                        self._record_access(add, wen, read_blocked_set, write_blocked_set)
                        self._write_req(f, id_value, wen, data, add); id_value += 1
                        if id_value - id_start >= self.N_TEST: break
                    if id_value - id_start >= self.N_TEST: break
                    for _ in range(idle_cycles_between_phases): self._write_idle(f)
                if id_value == emitted_before:
                    break
                k += 1
            self._write_pause(f)
        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("3d", id_start, id_value)
        return id_value

    def idle_gen(self, id_start, append=False):
        with self._open(append) as f:
            self._write_idle(f)
            self._write_pause(f)
        return id_start

    def matmul_phased_gen(self, id_start, read_blocked, write_blocked,
                          region_base_address, region_size_bytes,
                          matmul_ratio_a=1, matmul_ratio_b=1, matmul_ratio_c=1,
                          traffic_pct=100,
                          idle_cycles_between_phases=0,
                          region_base_address_a=None, region_size_bytes_a=None,
                          region_base_address_b=None, region_size_bytes_b=None,
                          region_base_address_c=None, region_size_bytes_c=None,
                          append=False):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = max(1, self.DATA_WIDTH // 8); tm = int(self.TOT_MEM_SIZE * 1024)
        n_idles = self._idles_per_req(traffic_pct)

        def _res(bo, so, fb, fs):
            b = self._align_down(int(bo if bo is not None else fb), ab)
            s = self._align_down(int(so if so is not None else fs), ab)
            if b+s > tm: s = self._align_down(tm-b, ab)
            return b, s

        if region_base_address_a is not None and region_size_bytes_a is not None:
            a_base, a_size = _res(region_base_address_a, region_size_bytes_a, 0, 0)
            b_base, b_size = _res(region_base_address_b, region_size_bytes_b, a_base, a_size)
            c_base, c_size = _res(region_base_address_c, region_size_bytes_c, a_base, a_size)
        else:
            base = self._align_down(int(region_base_address), ab)
            size = self._align_down(int(region_size_bytes), ab)
            if base+size > tm: size = self._align_down(tm-base, ab)
            rw = size // ab
            if rw < 3:
                with self._open(append) as f: self._write_idle(f); self._write_pause(f)
                self._require_exact_emits("matmul_phased", id_start, id_value)
                return id_value
            aw=max(1,rw//3); bw=max(1,rw//3); cw=rw-aw-bw
            a_base=base; a_size=aw*ab; b_base=a_base+a_size; b_size=bw*ab
            c_base=b_base+b_size; c_size=cw*ab

        ca, cb, cc = self._phase_counts(self.N_TEST, matmul_ratio_a, matmul_ratio_b, matmul_ratio_c)

        def _emit(fobj, count, wen, pb, pe):
            nonlocal id_value
            addr = pb
            for _ in range(count):
                data = "0"*self.DATA_WIDTH if wen else self.random_data()
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                    addr += ab
                    if addr >= pe:
                        addr = pb
                    continue
                self._write_req(fobj, id_value, wen, data, add)
                self._record_access(add, wen, read_blocked_set, write_blocked_set)
                id_value += 1; addr += ab
                if addr >= pe: addr = pb
                for _ in range(n_idles): self._write_idle(fobj)

        with self._open(append) as f:
            _emit(f, ca, 1, a_base, a_base+a_size)
            if ca > 0 and (cb > 0 or cc > 0):
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
            _emit(f, cb, 1, b_base, b_base+b_size)
            if cb > 0 and cc > 0:
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
            _emit(f, cc, 0, c_base, c_base+c_size)
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("matmul_phased", id_start, id_value)
        return id_value

    def multi_linear_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        regions,
        schedule="round_robin",
        burst_len=1,
        traffic_pct=100,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self.WIDTH_OF_MEMORY_BYTE
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        burst = max(1, int(burst_len))

        norm_regions = []
        for reg in regions or []:
            base = self._align_down(int(reg.get("base", 0)), ab)
            size = self._align_down(int(reg.get("size_bytes", 0)), ab)
            if size <= 0:
                continue
            if base >= tm:
                base %= tm
            if base + size > tm:
                size = self._align_down(tm - base, ab)
            if size <= 0:
                continue
            stride_words = max(1, int(reg.get("stride_words", 1)))
            read_pct = reg.get("read_pct")
            if read_pct is not None:
                read_pct = max(0, min(100, int(read_pct)))
            norm_regions.append({
                "base": base,
                "size": size,
                "stride_words": stride_words,
                "read_pct": read_pct,
                "offset": 0,
            })

        if not norm_regions:
            with self._open(append) as f:
                self._write_idle(f)
                self._write_pause(f)
            self._require_exact_emits("multi_linear", id_start, id_value)
            return id_value

        rr = 0
        stalled_rounds = 0
        with self._open(append) as f:
            while id_value - id_start < self.N_TEST:
                emitted_before = id_value
                reg = norm_regions[rr % len(norm_regions)]
                rr += 1
                chunk = burst if str(schedule).strip().lower() == "round_robin" else max(1, self.N_TEST)
                for _ in range(chunk):
                    if id_value - id_start >= self.N_TEST:
                        break
                    addr = reg["base"] + reg["offset"]
                    add = bin(self._normalize_addr(addr))[2:].zfill(self.ADD_WIDTH)
                    if reg["read_pct"] is None:
                        data, wen = self.data_wen()
                    else:
                        wen = 1 if random.randint(1, 100) <= reg["read_pct"] else 0
                        data = "0" * self.DATA_WIDTH if wen else self.random_data()
                    if self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                        self._record_access(add, wen, read_blocked_set, write_blocked_set)
                        self._write_req(f, id_value, wen, data, add)
                        id_value += 1
                        for _ in range(n_idles):
                            self._write_idle(f)
                    step = reg["stride_words"] * ab
                    reg["offset"] = (reg["offset"] + step) % reg["size"]
                if id_value == emitted_before:
                    stalled_rounds += 1
                    if stalled_rounds >= len(norm_regions):
                        break
                else:
                    stalled_rounds = 0
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("multi_linear", id_start, id_value)
        return id_value

    def bank_group_linear_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        start_bank,
        bank_group_span,
        stride_beats=1,
        bank_group_hop=0,
        wen=None,
        traffic_pct=100,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self.WIDTH_OF_MEMORY_BYTE
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        span = max(1, min(int(bank_group_span), int(self.N_BANKS)))
        start_bank = int(start_bank) % max(1, int(self.N_BANKS))
        stride = max(1, int(stride_beats))
        hop = max(0, int(bank_group_hop))

        with self._open(append) as f:
            for tx in range(self.N_TEST):
                phase = tx * stride
                group_idx = phase // span
                bank_base = (start_bank + group_idx * hop * span) % self.N_BANKS
                bank = (bank_base + (phase % span)) % self.N_BANKS
                row = group_idx
                word_idx = row * self.N_BANKS + bank
                addr = self._normalize_addr(word_idx * ab)
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                if wen is None:
                    data, wen_cur = self.data_wen()
                else:
                    wen_cur = 1 if int(wen) else 0
                    data = "0" * self.DATA_WIDTH if wen_cur else self.random_data()
                if not self._is_allowed(add, wen_cur, read_blocked_set, write_blocked_set):
                    continue
                self._record_access(add, wen_cur, read_blocked_set, write_blocked_set)
                self._write_req(f, id_value, wen_cur, data, add)
                id_value += 1
                for _ in range(n_idles):
                    self._write_idle(f)
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("bank_group_linear", id_start, id_value)
        return id_value

    def rw_rowwise_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        row_base_address,
        row_size_bytes,
        n_rows,
        row_stride_bytes,
        reads_per_row,
        writes_per_row,
        traffic_pct=100,
        idle_cycles_between_rows=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self.WIDTH_OF_MEMORY_BYTE
        n_idles = self._idles_per_req(traffic_pct)
        base = self._align_down(int(row_base_address), ab)
        row_size = max(ab, self._align_down(int(row_size_bytes), ab))
        row_stride = max(ab, self._align_down(int(row_stride_bytes), ab))
        n_rows = max(0, int(n_rows))
        reads_per_row = max(0, int(reads_per_row))
        writes_per_row = max(0, int(writes_per_row))

        with self._open(append) as f:
            for r in range(n_rows):
                if id_value - id_start >= self.N_TEST:
                    break
                row_base = self._normalize_addr(base + r * row_stride)
                for i in range(reads_per_row):
                    if id_value - id_start >= self.N_TEST:
                        break
                    addr = self._normalize_addr(row_base + (i * ab) % row_size)
                    add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                    wen = 1
                    data = "0" * self.DATA_WIDTH
                    if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                        continue
                    self._record_access(add, wen, read_blocked_set, write_blocked_set)
                    self._write_req(f, id_value, wen, data, add)
                    id_value += 1
                    for _ in range(n_idles):
                        self._write_idle(f)
                for i in range(writes_per_row):
                    if id_value - id_start >= self.N_TEST:
                        break
                    addr = self._normalize_addr(row_base + (i * ab) % row_size)
                    add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                    wen = 0
                    data = self.random_data()
                    if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                        continue
                    self._record_access(add, wen, read_blocked_set, write_blocked_set)
                    self._write_req(f, id_value, wen, data, add)
                    id_value += 1
                    for _ in range(n_idles):
                        self._write_idle(f)
                if r < n_rows - 1:
                    for _ in range(max(0, int(idle_cycles_between_rows))):
                        self._write_idle(f)
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("rw_rowwise", id_start, id_value)
        return id_value

    def gather_scatter_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        read_regions,
        write_region,
        chunk_bytes=0,
        schedule="4read_1write",
        traffic_pct=100,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self.WIDTH_OF_MEMORY_BYTE
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        chunk_val = ab if chunk_bytes is None else int(chunk_bytes)
        step = max(ab, self._align_down(chunk_val if chunk_val > 0 else ab, ab))
        tokens = self._parse_read_write_schedule(schedule)

        reads = []
        for reg in read_regions or []:
            base = self._align_down(int(reg.get("base", 0)), ab)
            size = self._align_down(int(reg.get("size_bytes", 0)), ab)
            if size <= 0:
                continue
            if base >= tm:
                base %= tm
            if base + size > tm:
                size = self._align_down(tm - base, ab)
            if size <= 0:
                continue
            reads.append({"base": base, "size": size, "offset": 0})

        wb = self._align_down(int((write_region or {}).get("base", 0)), ab)
        ws = self._align_down(int((write_region or {}).get("size_bytes", 0)), ab)
        if wb >= tm:
            wb %= tm
        if wb + ws > tm:
            ws = self._align_down(tm - wb, ab)

        if not reads and ws <= 0:
            with self._open(append) as f:
                self._write_idle(f)
                self._write_pause(f)
            self._require_exact_emits("gather_scatter", id_start, id_value)
            return id_value

        read_rr = 0
        token_idx = 0
        write_offset = 0
        max_no_progress = max(32, len(tokens) * max(1, len(reads) + (1 if ws > 0 else 0)))
        no_progress_iters = 0
        with self._open(append) as f:
            while id_value - id_start < self.N_TEST:
                token = tokens[token_idx % len(tokens)]
                token_idx += 1
                wen = 1 if token == "R" else 0
                if token == "R" and reads:
                    reg = reads[read_rr % len(reads)]
                    read_rr += 1
                    addr = self._normalize_addr(reg["base"] + reg["offset"])
                    reg["offset"] = (reg["offset"] + step) % reg["size"]
                elif ws > 0:
                    addr = self._normalize_addr(wb + write_offset)
                    write_offset = (write_offset + step) % ws
                elif reads:
                    reg = reads[read_rr % len(reads)]
                    read_rr += 1
                    wen = 1
                    addr = self._normalize_addr(reg["base"] + reg["offset"])
                    reg["offset"] = (reg["offset"] + step) % reg["size"]
                else:
                    break
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                data = "0" * self.DATA_WIDTH if wen else self.random_data()
                if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                    no_progress_iters += 1
                    if no_progress_iters >= max_no_progress:
                        break
                    continue
                self._record_access(add, wen, read_blocked_set, write_blocked_set)
                no_progress_iters = 0
                self._write_req(f, id_value, wen, data, add)
                id_value += 1
                for _ in range(n_idles):
                    self._write_idle(f)
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("gather_scatter", id_start, id_value)
        return id_value

    def matmul_tiled_interleave_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        region_base_address_a,
        region_size_bytes_a,
        region_base_address_b,
        region_size_bytes_b,
        region_base_address_c,
        region_size_bytes_c,
        tile_a_bytes=0,
        tile_b_bytes=0,
        tile_c_bytes=0,
        tiles=1,
        ab_c_schedule="A_B_C",
        traffic_pct=100,
        idle_cycles_between_tiles=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self.WIDTH_OF_MEMORY_BYTE
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        tile_idle = max(0, int(idle_cycles_between_tiles))
        tokens = self._parse_abc_schedule(ab_c_schedule)

        def _res(base_raw, size_raw):
            base = self._align_down(int(base_raw), ab)
            size = self._align_down(int(size_raw), ab)
            if base >= tm:
                base %= tm
            if base + size > tm:
                size = self._align_down(tm - base, ab)
            return base, size

        a_base, a_size = _res(region_base_address_a, region_size_bytes_a)
        b_base, b_size = _res(region_base_address_b, region_size_bytes_b)
        c_base, c_size = _res(region_base_address_c, region_size_bytes_c)
        if a_size <= 0 or b_size <= 0 or c_size <= 0:
            with self._open(append) as f:
                self._write_idle(f)
                self._write_pause(f)
            self._require_exact_emits("matmul_tiled_interleave", id_start, id_value)
            return id_value

        ta = ab if tile_a_bytes is None else int(tile_a_bytes)
        tb = ab if tile_b_bytes is None else int(tile_b_bytes)
        tc = ab if tile_c_bytes is None else int(tile_c_bytes)
        cnt_a = max(1, self._align_down(ta if ta > 0 else ab, ab) // ab)
        cnt_b = max(1, self._align_down(tb if tb > 0 else ab, ab) // ab)
        cnt_c = max(1, self._align_down(tc if tc > 0 else ab, ab) // ab)
        counts = {"A": cnt_a, "B": cnt_b, "C": cnt_c}
        ptr = {"A": 0, "B": 0, "C": 0}
        base = {"A": a_base, "B": b_base, "C": c_base}
        size = {"A": a_size, "B": b_size, "C": c_size}
        max_tiles = max(1, int(tiles))

        with self._open(append) as f:
            tile_idx = 0
            stalled_tiles = 0
            while id_value - id_start < self.N_TEST:
                emitted_before = id_value
                for tok in tokens:
                    for _ in range(counts[tok]):
                        if id_value - id_start >= self.N_TEST:
                            break
                        addr = self._normalize_addr(base[tok] + ptr[tok])
                        ptr[tok] = (ptr[tok] + ab) % size[tok]
                        wen = 0 if tok == "C" else 1
                        add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                        data = "0" * self.DATA_WIDTH if wen else self.random_data()
                        if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                            continue
                        self._record_access(add, wen, read_blocked_set, write_blocked_set)
                        self._write_req(f, id_value, wen, data, add)
                        id_value += 1
                        for _ in range(n_idles):
                            self._write_idle(f)
                tile_idx += 1
                if tile_idle > 0 and id_value - id_start < self.N_TEST:
                    for _ in range(tile_idle):
                        self._write_idle(f)
                if tile_idx >= max_tiles:
                    tile_idx = 0
                if id_value == emitted_before:
                    stalled_tiles += 1
                    if stalled_tiles >= max_tiles:
                        break
                else:
                    stalled_tiles = 0
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("matmul_tiled_interleave", id_start, id_value)
        return id_value

    def hotspot_random_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        hot_regions,
        traffic_pct=100,
        traffic_read_pct=None,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self.WIDTH_OF_MEMORY_BYTE
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)

        regions = []
        weights = []
        for reg in hot_regions or []:
            base = self._align_down(int(reg.get("base", 0)), ab)
            size = self._align_down(int(reg.get("size_bytes", 0)), ab)
            weight = max(1, int(reg.get("weight", 1)))
            if size <= 0:
                continue
            if base >= tm:
                base %= tm
            if base + size > tm:
                size = self._align_down(tm - base, ab)
            if size <= 0:
                continue
            regions.append({"base": base, "size": size})
            weights.append(weight)

        if not regions:
            with self._open(append) as f:
                self._write_idle(f)
                self._write_pause(f)
            self._require_exact_emits("hotspot_random", id_start, id_value)
            return id_value

        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1] * n_reads + [0] * (self.N_TEST - n_reads)
        else:
            wen_seq = None

        with self._open(append) as f:
            for i in range(self.N_TEST):
                reg = random.choices(regions, weights=weights, k=1)[0]
                n_words = max(1, reg["size"] // ab)
                ad = reg["base"] + random.randint(0, n_words - 1) * ab
                addr = self._normalize_addr(ad)
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                wen = wen_seq[i] if wen_seq is not None else None
                if wen is None:
                    data, wen = self.data_wen()
                else:
                    data = "0" * self.DATA_WIDTH if wen else self.random_data()
                if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                    continue
                self._record_access(add, wen, read_blocked_set, write_blocked_set)
                self._write_req(f, id_value, wen, data, add)
                id_value += 1
                for _ in range(n_idles):
                    self._write_idle(f)
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("hotspot_random", id_start, id_value)
        return id_value
