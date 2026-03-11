# HCI Verification Framework

## Overview

The verification framework drives configurable memory traffic from multiple masters through the HCI interconnect and measures throughput and latency. It is fully driven by three JSON configuration files:

For the up-to-date stimuli-generator pattern catalog and output format, see `target/verif/simvectors/README.md`.

| File | Purpose |
|------|---------|
| `config/hardware.json` | Interconnect topology (number of masters, banks, data widths, ...) |
| `config/testbench.json` | Simulation parameters (clock period, arbitration policy, ...) |
| `config/workload.json` | Per-master traffic patterns, transaction counts, and dataflow dependencies |

---

## Configuration files

### `hardware.json`

Controls the hardware topology instantiated in the testbench. Generates `config/generated/hardware.mk` which is included by the build system and passed as Verilog defines.

### `testbench.json`

Controls simulation-level knobs (clock period, reset cycles, arbitration parameters). Generates `config/generated/testbench.mk`.

### `workload.json`

The most user-facing configuration. Describes what each master does and in what order. Structure:

```json
{
  "description": "...",
  "log_masters": [ ... ],
  "hwpe_masters": [ ... ]
}
```

#### Per-master fields

Each entry in `log_masters` or `hwpe_masters` supports:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | recommended | Index within the master array. Must match the positional index (0-based). Used for documentation; mapping is always positional. |
| `description` | no | Human-readable label. |
| `mem_access_type` | yes | Traffic pattern. See [Access patterns](#access-patterns). |
| `n_transactions` | yes* | Number of transactions to issue. Can be derived from geometry for structured patterns — see below. |
| `phase` | no | Phase name (string). Masters in the same phase can run concurrently. Default: `"default"`. |
| `wait_for` | no | List of phase names that must complete (`end_req_o` asserted on all masters of those phases) before this master starts. Default: `[]` (start immediately). |
| `start_delay_cycles` | no | Number of idle cycles prepended to this master's stimuli file (static start delay within a phase). Default: `0`. |
| `region_base_address` | no | Base byte address of the memory region for this master (int, hex `0x...`, or decimal string). Default: evenly partitioned. |
| `region_size_bytes` | no | Size in bytes of the memory region for this master. Default: evenly partitioned. |
| `start_address` | no | Starting address for `linear`/`2d`/`3d` patterns (int, hex `0x...`, or decimal string). Default: `"0"`. |
| `stride0`, `len_d0` | no | Inner dimension stride (in words) and length for `linear`/`2d`/`3d`. |
| `stride1`, `len_d1` | no | Middle dimension stride (in words) and length for `2d`/`3d`. |
| `stride2` | no | Outer dimension stride (in words) for `3d`. |
| `traffic_pct` | no | [`random`, `linear`] Bus utilization percentage (1–100). After each transaction emits `floor((100-pct)/pct)` idle cycles. Default: `100` (back-to-back). |
| `traffic_read_pct` | no | [`random`, `linear`] Percentage of accesses that are reads. If omitted, read/write is random per transaction. When set, all reads are issued first, then all writes. |
| `idle_cycles_between_phases` | no | [`2d`, `3d`, `matmul_phased`] Idle cycles inserted between phases (between outer rows for `2d`/`3d`, between read-A/read-B/write-C for `matmul_phased`). Models compute time. Default: `0`. |
| `matmul_ratio_a/b/c` | no | [`matmul_phased`] Phase ratio for read-A : read-B : write-C transaction split. Default: `1:1:1`. |
| `region_base_address_a/b/c` | no | [`matmul_phased`] Explicit per-phase base addresses, overriding the auto-split of the combined region. |
| `region_size_bytes_a/b/c` | no | [`matmul_phased`] Explicit per-phase region sizes (paired with `region_base_address_a/b/c`). |

\* `n_transactions` can be omitted for structured patterns if geometry fields are provided — `main.py` derives it automatically and reports it. For `random` it is always required.

#### Deriving `n_transactions` from geometry

| Pattern | Geometry fields | Derived count |
|---------|----------------|---------------|
| `linear` | `length` | `length` |
| `2d` | `len_d0`, `len_d1` | `len_d0 × len_d1` |
| `3d` | `len_d0`, `len_d1`, `len_d2` | `len_d0 × len_d1 × len_d2` |
| `matmul_phased` | `matrix_m`, `matrix_n`, `matrix_k` | `m×k + k×n + m×n` |
| `random` | — | must be set explicitly |
| `idle` | — | ignored |

---

## Access patterns

| `mem_access_type` | Description |
|-------------------|-------------|
| `random` | Uniformly random addresses within the assigned region. |
| `linear` | Strided 1-D sequential scan. |
| `2d` | Strided 2-D scan (inner `stride0`/`len_d0`, outer `stride1`). |
| `3d` | Strided 3-D scan (inner `stride0`/`len_d0`, mid `stride1`/`len_d1`, outer `stride2`). |
| `matmul_phased` | Deterministic phased traffic modelling matrix multiply: read-A phase, read-B phase, write-C phase. The assigned region is split into three equal sub-regions A, B, C. |
| `idle` | No transactions (driver idles). |

---

## Dataflow: phases and dependencies

### Concept

Masters can be assigned to named **phases** and can declare **dependencies** on other phases. This allows modeling realistic dataflow graphs, e.g.:

- HWPE A and HWPE B run in parallel (same phase, no dependencies)
- HWPE C starts only after HWPE B finishes (C `wait_for: ["phaseB"]`)

```json
"hwpe_masters": [
  { "id": 0, "phase": "phaseA", "wait_for": [],           ... },
  { "id": 1, "phase": "phaseB", "wait_for": [],           ... },
  { "id": 2, "phase": "phaseC", "wait_for": ["phaseB"],   ... }
]
```

### Mechanism

`main.py` reads the `phase`/`wait_for` fields and computes a **wait mask** per driver: a bitmask of width `N_DRIVERS` where bit `j` is set if this driver must wait for driver `j`'s `end_req_o`. The masks are encoded as a SV unpacked array literal in `config/generated/fence_masks.mk` and passed to the simulator as the `WAIT_MASKS_PARAM` define.

In `tb_hci_pkg.sv`, `WAIT_MASKS[i]` holds driver `i`'s mask. In `tb_hci.sv`, each driver's `clear_i` is combinationally held high until all drivers in its mask have asserted `end_req_o`:

```
clear_i[i] = (eff_mask[i] != 0) && ((s_end_req & eff_mask[i]) != eff_mask[i])
```

A driver with an empty mask starts as soon as reset is released.

The dependency is on `end_req_o` (all transactions issued), not `end_resp_o` (all read responses retired). This is intentional: a dependent master can begin issuing as soon as the dependency master has issued all its requests, which is the correct model for pipelined HWPE dataflow.

### MUX mode (INTERCO_TYPE=MUX)

`hci_core_mux_static` forwards exactly one HWPE to the interconnect at a time (selected by `sel_i`). Therefore, in MUX mode **at most one HWPE can be active at any given time**, regardless of what `wait_for` says in the workload.

**The user-defined `wait_for` dependencies are ignored for HWPE drivers in MUX mode.** Instead, the testbench automatically enforces a strict sequential chain:

- HWPE 0 starts first (no dependency)
- HWPE 1 waits for HWPE 0
- HWPE 2 waits for HWPE 1
- ...
- HWPE k waits for HWPE k-1

**Ordering is by index**, which equals the positional order in the `hwpe_masters` array in `workload.json` (0-based). To control execution order in MUX mode, reorder the entries in `hwpe_masters`.

LOG master `wait_for` dependencies are always respected regardless of interconnect mode.

`sel_i` is driven combinationally to the index of the currently active HWPE (the lowest-indexed HWPE whose `clear_i` is 0).

This means **the same workload JSON can be used across all three interconnect modes** (HCI, MUX, LOG). In HCI/LOG mode the declared `wait_for` dependencies are honored; in MUX mode they are overridden by the sequential chain.

---

## Memory layout

The memory uses a **bank-interleaved addressing scheme**: consecutive word addresses map to consecutive banks before wrapping.

```
byte addr 0x00  → bank 0
byte addr 0x04  → bank 1   (assuming DATA_WIDTH=32, 4 bytes/word)
...
byte addr 0x7C  → bank 31  (for N_BANKS=32)
byte addr 0x80  → bank 0   (wrap)
```

In general, bank index = `(byte_addr / (DATA_WIDTH/8)) % N_BANKS`.

`main.py` reports the memory map for each master after stimuli generation, showing:
- First and last byte addresses accessed
- Total transfer size in bytes
- Number of distinct banks touched
- For matmul_phased: sub-region boundaries for A, B, C matrices

This allows verifying that regions are correctly partitioned and identifying any unintended overlaps between masters.

---

## Build targets

| Target | Action |
|--------|--------|
| `make config-verif` | Generate `hardware.mk`, `testbench.mk` from JSON |
| `make stim-verif` | Generate stimuli and `fence_masks.mk` from workload/hardware/testbench JSON |
| `make compile-verif` | Compile RTL and testbench with QuestaSim |
| `make opt-verif` | Optimize compiled design |
| `make run-verif` | Run simulation |
| `make clean-verif` | Remove all generated artifacts |

Pass `WORKLOAD_JSON=config/workload_<name>.json` to `make stim-verif` / `make run-verif` to select an alternative workload.
