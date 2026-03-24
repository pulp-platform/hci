"""Access-pattern generators for StimuliGenerator.

Each method writes a cycle-accurate stimuli file directly (one line per cycle):
  req(1b) id(IWb) wen(1b) be(BEWb) data(Nb) add(Ab)

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

    def _be_for(self, tx_index, n_total, trailing_bytes):
        """Return the byte-enable string for transaction tx_index (0-based) in a sequence of n_total.

        All beats use full be (all-ones) except the last beat when trailing_bytes > 0,
        which gets a partial be with bits [trailing_bytes-1:0] set.

        trailing_bytes=0 (default) means all transactions are full beats.
        """
        if trailing_bytes > 0 and tx_index == n_total - 1:
            return self._partial_be(trailing_bytes)
        return self._full_be()

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
        a = int(addr)
        end = a + self._ab
        if a < 0 or end > total:
            raise ValueError(
                f"address 0x{a:X} (end 0x{end:X}) exceeds total memory "
                f"0x{total:X} ({self.TOT_MEM_SIZE} KiB)"
            )
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
                   traffic_read_pct=None, trailing_bytes=0, append=False):
        total = int(self.TOT_MEM_SIZE * 1024)
        if region_size is None: region_size = total
        if region_base < 0 or region_base >= total:
            raise ValueError(
                f"random: region_base 0x{region_base:X} is out of range [0, 0x{total:X})"
            )
        if region_base + region_size > total:
            raise ValueError(
                f"random: region end 0x{region_base + region_size:X} exceeds total memory 0x{total:X}"
            )
        n_words = max(1, region_size // self._ab)
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
        tx_idx = 0
        with self._open(append) as f:
            for i in range(self.N_TEST):
                wen = wen_seq[i] if wen_seq is not None else None
                if wen is None: data, wen = self.data_wen()
                else: data = "0"*self.DATA_WIDTH if wen else self.random_data()
                placed = False
                for _ in range(max_attempts):
                    ad = region_base + random.randint(0, int(n_words)-1)*self._ab
                    add = bin(int(ad))[2:].zfill(self.ADD_WIDTH)
                    if self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                        self._record_access(add, wen, read_blocked_set, write_blocked_set)
                        placed = True
                        break
                if not placed:
                    continue
                be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                self._write_req(f, id_value, wen, data, add, be=be); id_value += 1; tx_idx += 1
                for _ in range(n_idles): self._write_idle(f)
            self._write_pause(f)
        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("random", id_start, id_value)
        return id_value

    def linear_gen(self, stride0, start_address, id_start, read_blocked, write_blocked,
                   traffic_pct=100, traffic_read_pct=None, trailing_bytes=0, append=False):
        n_idles = self._idles_per_req(traffic_pct)
        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1]*n_reads + [0]*(self.N_TEST-n_reads)
        else:
            wen_seq = None
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        tx_idx = 0
        total = self._total_mem_bytes()
        with self._open(append) as f:
            addr = self._parse_address(start_address)
            if addr < 0 or addr + self._ab > total:
                raise ValueError(
                    f"linear: start_address 0x{addr:X} (end 0x{addr + self._ab:X}) "
                    f"exceeds total memory 0x{total:X}"
                )
            for i in range(self.N_TEST):
                wen = wen_seq[i] if wen_seq is not None else None
                if wen is None: data, wen = self.data_wen()
                else: data = "0"*self.DATA_WIDTH if wen else self.random_data()
                if addr < 0 or addr + self._ab > total:
                    raise ValueError(
                        f"linear: address 0x{addr:X} (end 0x{addr + self._ab:X}) "
                        f"exceeds total memory 0x{total:X} at transaction {i}"
                    )
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                addr += self._ab * stride0
                if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set): continue
                self._record_access(add, wen, read_blocked_set, write_blocked_set)
                be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                self._write_req(f, id_value, wen, data, add, be=be); id_value += 1; tx_idx += 1
                for _ in range(n_idles): self._write_idle(f)
            self._write_pause(f)
        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("linear", id_start, id_value)
        return id_value

    def gen_2d(self, stride0, len_d0, stride1, start_address, id_start,
               read_blocked, write_blocked, idle_cycles_between_phases=0,
               trailing_bytes=0, append=False):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        tx_idx = 0
        total = self._total_mem_bytes()
        with self._open(append) as f:
            base = self._parse_address(start_address); j = 0
            while id_value - id_start < self.N_TEST:
                emitted_before = id_value
                for i in range(len_d0):
                    data, wen = self.data_wen()
                    addr = base + i*self._ab*stride0 + j*self._ab*stride1
                    if addr < 0 or addr + self._ab > total:
                        raise ValueError(
                            f"2d: address 0x{addr:X} (end 0x{addr + self._ab:X}) "
                            f"exceeds total memory 0x{total:X} at i={i}, j={j}"
                        )
                    add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                    if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set): continue
                    self._record_access(add, wen, read_blocked_set, write_blocked_set)
                    be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                    self._write_req(f, id_value, wen, data, add, be=be); id_value += 1; tx_idx += 1
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
               read_blocked, write_blocked, idle_cycles_between_phases=0,
               trailing_bytes=0, append=False):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        tx_idx = 0
        total = self._total_mem_bytes()
        with self._open(append) as f:
            base = self._parse_address(start_address); k = 0
            while id_value - id_start < self.N_TEST:
                emitted_before = id_value
                for j in range(len_d1):
                    for i in range(len_d0):
                        data, wen = self.data_wen()
                        addr = base + i*self._ab*stride0 + j*self._ab*stride1 + k*self._ab*stride2
                        if addr < 0 or addr + self._ab > total:
                            raise ValueError(
                                f"3d: address 0x{addr:X} (end 0x{addr + self._ab:X}) "
                                f"exceeds total memory 0x{total:X} at i={i}, j={j}, k={k}"
                            )
                        add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                        if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set): continue
                        self._record_access(add, wen, read_blocked_set, write_blocked_set)
                        be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                        self._write_req(f, id_value, wen, data, add, be=be); id_value += 1; tx_idx += 1
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
                          trailing_bytes_a=0, trailing_bytes_b=0, trailing_bytes_c=0,
                          append=False):
        """Phased A-read / B-read / C-write traffic.

        trailing_bytes_a/b/c: if > 0, the last transaction of that phase uses a
        partial byte-enable covering only the specified number of valid bytes.
        This models a transfer whose total byte size is not a multiple of the bus
        width (e.g. an int8 matrix whose element count does not divide evenly into
        32-byte bus beats). When n_transactions is derived from matrix dims via
        matrix_m/n/k, main.py computes these automatically. When n_transactions is
        set explicitly, all beats are assumed full (trailing_bytes=0).
        """
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = max(1, self.DATA_WIDTH // 8); tm = int(self.TOT_MEM_SIZE * 1024)
        n_idles = self._idles_per_req(traffic_pct)

        def _res(bo, so, fb, fs, label="region"):
            b = self._align_down(int(bo if bo is not None else fb), ab)
            s = self._align_down(int(so if so is not None else fs), ab)
            if b < 0 or b >= tm:
                raise ValueError(f"matmul_phased: {label} base 0x{b:X} is out of range [0, 0x{tm:X})")
            if s <= 0:
                raise ValueError(f"matmul_phased: {label} size {s} <= 0")
            if b + s > tm:
                raise ValueError(
                    f"matmul_phased: {label} end 0x{b+s:X} exceeds total memory 0x{tm:X}"
                )
            return b, s

        if region_base_address_a is not None and region_size_bytes_a is not None:
            a_base, a_size = _res(region_base_address_a, region_size_bytes_a, 0, 0, "A")
            b_base, b_size = _res(region_base_address_b, region_size_bytes_b, a_base, a_size, "B")
            c_base, c_size = _res(region_base_address_c, region_size_bytes_c, a_base, a_size, "C")
        else:
            base = self._align_down(int(region_base_address), ab)
            size = self._align_down(int(region_size_bytes), ab)
            if base < 0 or base >= tm:
                raise ValueError(f"matmul_phased: base 0x{base:X} is out of range [0, 0x{tm:X})")
            if size <= 0:
                raise ValueError(f"matmul_phased: size {size} <= 0")
            if base + size > tm:
                raise ValueError(f"matmul_phased: end 0x{base+size:X} exceeds total memory 0x{tm:X}")
            rw = size // ab
            if rw < 3:
                with self._open(append) as f: self._write_idle(f); self._write_pause(f)
                self._require_exact_emits("matmul_phased", id_start, id_value)
                return id_value
            aw=max(1,rw//3); bw=max(1,rw//3); cw=rw-aw-bw
            a_base=base; a_size=aw*ab; b_base=a_base+a_size; b_size=bw*ab
            c_base=b_base+b_size; c_size=cw*ab

        ca, cb, cc = self._phase_counts(self.N_TEST, matmul_ratio_a, matmul_ratio_b, matmul_ratio_c)

        def _emit(fobj, count, wen, pb, pe, trailing_bytes):
            nonlocal id_value
            addr = pb
            tx_idx = 0
            for _ in range(count):
                data = "0"*self.DATA_WIDTH if wen else self.random_data()
                add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                    addr += ab
                    if addr >= pe:
                        addr = pb
                    continue
                be = self._be_for(tx_idx, count, trailing_bytes)
                self._write_req(fobj, id_value, wen, data, add, be=be)
                self._record_access(add, wen, read_blocked_set, write_blocked_set)
                id_value += 1; tx_idx += 1; addr += ab
                if addr >= pe: addr = pb
                for _ in range(n_idles): self._write_idle(fobj)

        with self._open(append) as f:
            _emit(f, ca, 1, a_base, a_base+a_size, trailing_bytes_a)
            if ca > 0 and (cb > 0 or cc > 0):
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
            _emit(f, cb, 1, b_base, b_base+b_size, trailing_bytes_b)
            if cb > 0 and cc > 0:
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
            _emit(f, cc, 0, c_base, c_base+c_size, trailing_bytes_c)
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
        trailing_bytes=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        burst = max(1, int(burst_len))

        norm_regions = []
        for reg in regions or []:
            base = self._align_down(int(reg.get("base", 0)), ab)
            size = self._align_down(int(reg.get("size_bytes", 0)), ab)
            if size <= 0:
                continue
            if base < 0 or base >= tm:
                raise ValueError(
                    f"multi_linear: region base 0x{base:X} is out of range [0, 0x{tm:X})"
                )
            if base + size > tm:
                raise ValueError(
                    f"multi_linear: region end 0x{base+size:X} exceeds total memory 0x{tm:X}"
                )
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
        tx_idx = 0
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
                        be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                        self._write_req(f, id_value, wen, data, add, be=be)
                        id_value += 1; tx_idx += 1
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
        trailing_bytes=0,
        append=False,
    ):
        if self._ab > self.WIDTH_OF_MEMORY_BYTE:
            raise ValueError(
                f"bank_group_linear: pattern targets individual bank words ({self.WIDTH_OF_MEMORY_BYTE} B) "
                f"and cannot be used with a wide-bus master (DATA_WIDTH={self.DATA_WIDTH} bits, "
                f"access={self._ab} B). Use a log/core master instead."
            )
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        span = max(1, min(int(bank_group_span), int(self.N_BANKS)))
        start_bank = int(start_bank) % max(1, int(self.N_BANKS))
        stride = max(1, int(stride_beats))
        hop = max(0, int(bank_group_hop))

        tx_idx = 0
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
                be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                self._write_req(f, id_value, wen_cur, data, add, be=be)
                id_value += 1; tx_idx += 1
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
        trailing_bytes=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
        n_idles = self._idles_per_req(traffic_pct)
        base = self._align_down(int(row_base_address), ab)
        row_size = max(ab, self._align_down(int(row_size_bytes), ab))
        row_stride = max(ab, self._align_down(int(row_stride_bytes), ab))
        n_rows = max(0, int(n_rows))
        reads_per_row = max(0, int(reads_per_row))
        writes_per_row = max(0, int(writes_per_row))

        tx_idx = 0
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
                    # Don't record reads: rw_rowwise is an RMW pattern where writes
                    # intentionally target the same addresses as the preceding reads.
                    # Recording reads would populate write_blocked_set and block all writes.
                    # self._record_access(add, wen, read_blocked_set, write_blocked_set)
                    be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                    self._write_req(f, id_value, wen, data, add, be=be)
                    id_value += 1; tx_idx += 1
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
                    be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                    self._write_req(f, id_value, wen, data, add, be=be)
                    id_value += 1; tx_idx += 1
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
        trailing_bytes=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
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
            if base < 0 or base >= tm:
                raise ValueError(
                    f"gather_scatter: read region base 0x{base:X} is out of range [0, 0x{tm:X})"
                )
            if base + size > tm:
                raise ValueError(
                    f"gather_scatter: read region end 0x{base+size:X} exceeds total memory 0x{tm:X}"
                )
            reads.append({"base": base, "size": size, "offset": 0})

        wb = self._align_down(int((write_region or {}).get("base", 0)), ab)
        ws = self._align_down(int((write_region or {}).get("size_bytes", 0)), ab)
        if ws > 0:
            if wb < 0 or wb >= tm:
                raise ValueError(
                    f"gather_scatter: write region base 0x{wb:X} is out of range [0, 0x{tm:X})"
                )
            if wb + ws > tm:
                raise ValueError(
                    f"gather_scatter: write region end 0x{wb+ws:X} exceeds total memory 0x{tm:X}"
                )

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
        tx_idx = 0
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
                be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                self._write_req(f, id_value, wen, data, add, be=be)
                id_value += 1; tx_idx += 1
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
        trailing_bytes=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)
        tile_idle = max(0, int(idle_cycles_between_tiles))
        tokens = self._parse_abc_schedule(ab_c_schedule)

        def _res(base_raw, size_raw, label="region"):
            base = self._align_down(int(base_raw), ab)
            size = self._align_down(int(size_raw), ab)
            if base < 0 or base >= tm:
                raise ValueError(
                    f"matmul_tiled_interleave: {label} base 0x{base:X} is out of range [0, 0x{tm:X})"
                )
            if size <= 0:
                raise ValueError(f"matmul_tiled_interleave: {label} size {size} <= 0")
            if base + size > tm:
                raise ValueError(
                    f"matmul_tiled_interleave: {label} end 0x{base+size:X} exceeds total memory 0x{tm:X}"
                )
            return base, size

        a_base, a_size = _res(region_base_address_a, region_size_bytes_a, "A")
        b_base, b_size = _res(region_base_address_b, region_size_bytes_b, "B")
        c_base, c_size = _res(region_base_address_c, region_size_bytes_c, "C")
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

        tx_idx = 0
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
                        be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                        self._write_req(f, id_value, wen, data, add, be=be)
                        id_value += 1; tx_idx += 1
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
        trailing_bytes=0,
        append=False,
    ):
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
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
            if base < 0 or base >= tm:
                raise ValueError(
                    f"hotspot_random: region base 0x{base:X} is out of range [0, 0x{tm:X})"
                )
            if base + size > tm:
                raise ValueError(
                    f"hotspot_random: region end 0x{base+size:X} exceeds total memory 0x{tm:X}"
                )
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

        tx_idx = 0
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
                be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
                self._write_req(f, id_value, wen, data, add, be=be)
                id_value += 1; tx_idx += 1
                for _ in range(n_idles):
                    self._write_idle(f)
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("hotspot_random", id_start, id_value)
        return id_value

    def copy_linear_gen(self, id_start, read_blocked, write_blocked,
                        src_base_address, src_size_bytes,
                        dst_base_address, dst_size_bytes,
                        traffic_pct=100, append=False):
        """Interleaved read-from-src / write-to-dst streaming copy pattern.

        Models a streaming copy/pack engine (e.g. DataMover doing im2col/pack):
        alternates read[src_i] / write[dst_i] pairs up to N_TEST total transactions.
        N_TEST should be even (n_copy_ops * 2) for a balanced 50% R / 50% W model.
        """
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)

        src_base = self._align_down(int(src_base_address), ab)
        src_size = self._align_down(int(src_size_bytes), ab)
        dst_base = self._align_down(int(dst_base_address), ab)
        dst_size = self._align_down(int(dst_size_bytes), ab)

        for label, base, size in [("src", src_base, src_size), ("dst", dst_base, dst_size)]:
            if base < 0 or base >= tm:
                raise ValueError(f"copy_linear: {label} base 0x{base:X} out of range [0, 0x{tm:X})")
            if size <= 0:
                raise ValueError(f"copy_linear: {label} size {size} <= 0")
            if base + size > tm:
                raise ValueError(f"copy_linear: {label} end 0x{base+size:X} exceeds total memory 0x{tm:X}")

        src_addr = src_base
        dst_addr = dst_base
        is_read = True

        with self._open(append) as f:
            while id_value - id_start < self.N_TEST:
                if is_read:
                    add = bin(self._normalize_addr(src_addr))[2:].zfill(self.ADD_WIDTH)
                    if self._is_allowed(add, 1, read_blocked_set, write_blocked_set):
                        self._record_access(add, 1, read_blocked_set, write_blocked_set)
                        self._write_req(f, id_value, 1, "0" * self.DATA_WIDTH, add)
                        id_value += 1
                        for _ in range(n_idles):
                            self._write_idle(f)
                    src_addr += ab
                    if src_addr >= src_base + src_size:
                        src_addr = src_base
                else:
                    add = bin(self._normalize_addr(dst_addr))[2:].zfill(self.ADD_WIDTH)
                    if self._is_allowed(add, 0, read_blocked_set, write_blocked_set):
                        self._record_access(add, 0, read_blocked_set, write_blocked_set)
                        self._write_req(f, id_value, 0, self.random_data(), add)
                        id_value += 1
                        for _ in range(n_idles):
                            self._write_idle(f)
                    dst_addr += ab
                    if dst_addr >= dst_base + dst_size:
                        dst_addr = dst_base
                is_read = not is_read
            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("copy_linear", id_start, id_value)
        return id_value

    def depthwise_windowed_gen(
        self,
        id_start,
        read_blocked,
        write_blocked,
        input_base_address,
        input_row_stride_bytes,
        input_channel_stride_bytes,
        weight_base_address,
        weight_channel_stride_bytes,
        output_base_address,
        output_row_stride_bytes,
        output_channel_stride_bytes,
        out_h,
        out_w,
        channels,
        kernel_h=3,
        kernel_w=3,
        stride_h=1,
        stride_w=1,
        pad_h=0,
        pad_w=0,
        channel_group=1,
        include_weights=True,
        output_writes_per_point=1,
        traffic_pct=100,
        idle_cycles_between_rows=0,
        idle_cycles_between_groups=0,
        trailing_bytes=0,
        append=False,
    ):
        """
        Approximate a depthwise-convolution accelerator traffic pattern.

        Semantics:
          - For each channel group:
              - optional compact kernel-bank reads
              - for each output point: read KH*KW input-window elements from the same channel
              - write output_writes_per_point output beats per output point
          - Address generation is structured over channel, row, col, kernel_r, kernel_c.
          - Padding is modeled by skipping out-of-bounds input reads (no transaction emitted).

        This models a direct depthwise datapath better than GEMM/im2col, but it still
        does not represent internal line-buffer reuse explicitly.
        """
        id_value = id_start
        read_blocked_set, write_blocked_set = self._init_blocked_sets(read_blocked, write_blocked)
        ab = self._ab
        tm = self._total_mem_bytes()
        n_idles = self._idles_per_req(traffic_pct)

        in_base = self._align_down(int(input_base_address), ab)
        in_row = max(ab, self._align_down(int(input_row_stride_bytes), ab))
        in_ch = max(in_row, self._align_down(int(input_channel_stride_bytes), ab))
        wt_base = self._align_down(int(weight_base_address), ab)
        wt_ch = max(ab, self._align_down(int(weight_channel_stride_bytes), ab))
        out_base = self._align_down(int(output_base_address), ab)
        out_row = max(ab, self._align_down(int(output_row_stride_bytes), ab))
        out_ch = max(out_row, self._align_down(int(output_channel_stride_bytes), ab))

        out_h = max(0, int(out_h))
        out_w = max(0, int(out_w))
        channels = max(0, int(channels))
        kernel_h = max(1, int(kernel_h))
        kernel_w = max(1, int(kernel_w))
        stride_h = max(1, int(stride_h))
        stride_w = max(1, int(stride_w))
        pad_h = max(0, int(pad_h))
        pad_w = max(0, int(pad_w))
        channel_group = max(1, int(channel_group))
        output_writes_per_point = max(1, int(output_writes_per_point))
        groups = max(1, (channels + channel_group - 1) // channel_group)

        def _safe_emit(fobj, addr, wen, tx_idx):
            nonlocal id_value
            addr = self._normalize_addr(addr)
            add = bin(addr)[2:].zfill(self.ADD_WIDTH)
            data = "0" * self.DATA_WIDTH if wen else self.random_data()
            if not self._is_allowed(add, wen, read_blocked_set, write_blocked_set):
                return tx_idx, False
            self._record_access(add, wen, read_blocked_set, write_blocked_set)
            be = self._be_for(tx_idx, self.N_TEST, trailing_bytes)
            self._write_req(fobj, id_value, wen, data, add, be=be)
            id_value += 1
            tx_idx += 1
            for _ in range(n_idles):
                self._write_idle(fobj)
            return tx_idx, True

        tx_idx = 0
        with self._open(append) as f:
            for g in range(groups):
                c_start = g * channel_group
                c_end = min(channels, c_start + channel_group)

                if include_weights:
                    for c in range(c_start, c_end):
                        for kr in range(kernel_h):
                            for kc in range(kernel_w):
                                if id_value - id_start >= self.N_TEST:
                                    break
                                w_addr = wt_base + c * wt_ch + (kr * kernel_w + kc) * ab
                                tx_idx, _ = _safe_emit(f, w_addr, 1, tx_idx)
                            if id_value - id_start >= self.N_TEST:
                                break
                        if id_value - id_start >= self.N_TEST:
                            break

                if id_value - id_start >= self.N_TEST:
                    break

                for oh in range(out_h):
                    emitted_before_row = id_value
                    for ow in range(out_w):
                        for c in range(c_start, c_end):
                            in_h0 = oh * stride_h - pad_h
                            in_w0 = ow * stride_w - pad_w

                            for kr in range(kernel_h):
                                for kc in range(kernel_w):
                                    if id_value - id_start >= self.N_TEST:
                                        break
                                    ih = in_h0 + kr
                                    iw = in_w0 + kc

                                    if ih < 0 or iw < 0:
                                        continue

                                    in_addr = in_base + c * in_ch + ih * in_row + iw * ab
                                    if in_addr < 0 or in_addr + ab > tm:
                                        continue
                                    tx_idx, _ = _safe_emit(f, in_addr, 1, tx_idx)
                                if id_value - id_start >= self.N_TEST:
                                    break
                            if id_value - id_start >= self.N_TEST:
                                break

                            out_addr = out_base + c * out_ch + oh * out_row + ow * ab
                            for _ in range(output_writes_per_point):
                                if id_value - id_start >= self.N_TEST:
                                    break
                                tx_idx, _ = _safe_emit(f, out_addr, 0, tx_idx)
                            if id_value - id_start >= self.N_TEST:
                                break
                        if id_value - id_start >= self.N_TEST:
                            break

                    if oh < out_h - 1 and id_value > emitted_before_row:
                        for _ in range(max(0, int(idle_cycles_between_rows))):
                            self._write_idle(f)

                    if id_value - id_start >= self.N_TEST:
                        break

                if g < groups - 1:
                    for _ in range(max(0, int(idle_cycles_between_groups))):
                        self._write_idle(f)

                if id_value - id_start >= self.N_TEST:
                    break

            self._write_pause(f)

        self._commit_blocked_sets(read_blocked, write_blocked, read_blocked_set, write_blocked_set)
        self._require_exact_emits("depthwise_windowed", id_start, id_value)
        return id_value