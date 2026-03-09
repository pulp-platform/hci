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

    def _is_allowed(self, add, wen, fr, fw):
        return add not in (fr if wen else fw)

    def _record_access(self, add, wen, fr_new, fw_new):
        fw_new.append(add)
        if not wen: fr_new.append(add)

    def _open(self, append):
        return open(self.filepath, "a" if append else "w", encoding="ascii")

    # ------------------------------------------------------------------ #
    # Access patterns — each writes: transactions | PAUSE                 #
    # ------------------------------------------------------------------ #

    def random_gen(self, id_start, forbidden_read, forbidden_write,
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
        id_value = id_start; fr_new, fw_new = [], []
        with self._open(append) as f:
            for i in range(self.N_TEST):
                wen = wen_seq[i] if wen_seq is not None else None
                if wen is None: data, wen = self.data_wen()
                else: data = "0"*self.DATA_WIDTH if wen else self.random_data()
                while True:
                    ad = region_base + random.randint(0, int(n_words)-1)*self.WIDTH_OF_MEMORY_BYTE
                    add = bin(int(ad))[2:].zfill(self.ADD_WIDTH)
                    if self._is_allowed(add, wen, forbidden_read, forbidden_write):
                        self._record_access(add, wen, fr_new, fw_new); break
                self._write_req(f, id_value, wen, data, add); id_value += 1
                for _ in range(n_idles): self._write_idle(f)
            self._write_pause(f)
        forbidden_read.extend(fr_new); forbidden_write.extend(fw_new)
        return id_value

    def linear_gen(self, stride0, start_address, id_start, forbidden_read, forbidden_write,
                   traffic_pct=100, traffic_read_pct=None, append=False):
        n_idles = self._idles_per_req(traffic_pct)
        if traffic_read_pct is not None:
            rpct = max(0, min(100, int(traffic_read_pct)))
            n_reads = (self.N_TEST * rpct) // 100
            wen_seq = [1]*n_reads + [0]*(self.N_TEST-n_reads)
        else:
            wen_seq = None
        id_value = id_start; fr_new, fw_new = [], []
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
                if not self._is_allowed(add, wen, forbidden_read, forbidden_write): continue
                self._record_access(add, wen, fr_new, fw_new)
                self._write_req(f, id_value, wen, data, add); id_value += 1
                for _ in range(n_idles): self._write_idle(f)
            self._write_pause(f)
        forbidden_read.extend(fr_new); forbidden_write.extend(fw_new)
        return id_value

    def gen_2d(self, stride0, len_d0, stride1, start_address, id_start,
               forbidden_read, forbidden_write, idle_cycles_between_phases=0, append=False):
        id_value = id_start; fr_new, fw_new = [], []
        with self._open(append) as f:
            base = self._parse_address(start_address); j = 0
            while id_value - id_start < self.N_TEST:
                for i in range(len_d0):
                    data, wen = self.data_wen()
                    addr = base + i*self.WIDTH_OF_MEMORY_BYTE*stride0 + j*self.WIDTH_OF_MEMORY_BYTE*stride1
                    if addr > self.TOT_MEM_SIZE*1024 - self.WIDTH_OF_MEMORY_BYTE:
                        addr -= self.TOT_MEM_SIZE*1024
                    add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                    if not self._is_allowed(add, wen, forbidden_read, forbidden_write): continue
                    self._record_access(add, wen, fr_new, fw_new)
                    self._write_req(f, id_value, wen, data, add); id_value += 1
                    if id_value - id_start >= self.N_TEST: break
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
                j += 1
            self._write_pause(f)
        forbidden_read.extend(fr_new); forbidden_write.extend(fw_new)
        return id_value

    def gen_3d(self, stride0, len_d0, stride1, len_d1, stride2, start_address, id_start,
               forbidden_read, forbidden_write, idle_cycles_between_phases=0, append=False):
        id_value = id_start; fr_new, fw_new = [], []
        with self._open(append) as f:
            base = self._parse_address(start_address); k = 0
            while id_value - id_start < self.N_TEST:
                for j in range(len_d1):
                    for i in range(len_d0):
                        data, wen = self.data_wen()
                        addr = base + i*self.WIDTH_OF_MEMORY_BYTE*stride0 + j*self.WIDTH_OF_MEMORY_BYTE*stride1 + k*self.WIDTH_OF_MEMORY_BYTE*stride2
                        if addr > self.TOT_MEM_SIZE*1024 - self.WIDTH_OF_MEMORY_BYTE:
                            addr -= self.TOT_MEM_SIZE*1024
                        add = bin(addr)[2:].zfill(self.ADD_WIDTH)
                        if not self._is_allowed(add, wen, forbidden_read, forbidden_write): continue
                        self._record_access(add, wen, fr_new, fw_new)
                        self._write_req(f, id_value, wen, data, add); id_value += 1
                        if id_value - id_start >= self.N_TEST: break
                    if id_value - id_start >= self.N_TEST: break
                    for _ in range(idle_cycles_between_phases): self._write_idle(f)
                k += 1
            self._write_pause(f)
        forbidden_read.extend(fr_new); forbidden_write.extend(fw_new)
        return id_value

    def idle_gen(self, id_start, append=False):
        with self._open(append) as f:
            self._write_idle(f)
            self._write_pause(f)
        return id_start

    def matmul_phased_gen(self, id_start, forbidden_read, forbidden_write,
                          region_base_address, region_size_bytes,
                          matmul_ratio_a=1, matmul_ratio_b=1, matmul_ratio_c=1,
                          idle_cycles_between_phases=0,
                          region_base_address_a=None, region_size_bytes_a=None,
                          region_base_address_b=None, region_size_bytes_b=None,
                          region_base_address_c=None, region_size_bytes_c=None,
                          append=False):
        id_value = id_start; fr_new, fw_new = [], []
        ab = max(1, self.DATA_WIDTH // 8); tm = int(self.TOT_MEM_SIZE * 1024)

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
                self._write_req(fobj, id_value, wen, data, add)
                self._record_access(add, wen, fr_new, fw_new)
                id_value += 1; addr += ab
                if addr >= pe: addr = pb

        with self._open(append) as f:
            _emit(f, ca, 1, a_base, a_base+a_size)
            if ca > 0 and (cb > 0 or cc > 0):
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
            _emit(f, cb, 1, b_base, b_base+b_size)
            if cb > 0 and cc > 0:
                for _ in range(idle_cycles_between_phases): self._write_idle(f)
            _emit(f, cc, 0, c_base, c_base+c_size)
            self._write_pause(f)

        forbidden_read.extend(fr_new); forbidden_write.extend(fw_new)
        return id_value
