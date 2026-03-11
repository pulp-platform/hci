# Simvectors Stimuli Generator

## Scope
`main.py` generates per-master stimuli vectors from:
- `workload.json`
- `hardware.json`
- `testbench.json`

This README summarizes:
- available `mem_access_type` patterns and JSON parameters
- every source of `req=0` cycles
- read/write blocked-set behavior
- generated outputs and formats

## JSON Structure (workload)
Top-level:
- `log_masters`: list of narrow masters
- `hwpe_masters`: list of wide masters

### Field Format Conventions
| Kind | Accepted JSON format | Unit / meaning |
|---|---|---|
| Address fields (`*_address`, `base`) | integer or string (`"1234"`, `"0x4000"`, `"101010"`) | byte address |
| Size fields (`*_size_bytes`, `chunk_bytes`, `tile_*_bytes`) | integer or numeric string | bytes |
| Strides (`stride0/1/2`) | integer | words (word = `DATA_WIDTH/8` for that master) |
| `row_stride_bytes` | integer or numeric string | bytes |
| `stride_beats` | integer | beats (beat = transaction width in bytes for that master) |
| Counters (`n_transactions`, `len_*`, `tiles`, `reads_per_row`, `writes_per_row`) | integer | count |
| Percentages (`traffic_pct`, `traffic_read_pct`, `read_pct`) | integer | percent |
| `wen` | `0` or `1` | `0`=write, `1`=read |

### Master-Level Fields
| Field | Required | Default | Notes |
|---|---|---|---|
| `id` | no | positional index | Informational/consistency warning only. |
| `description` | no | empty | Human-readable label. |
| `start_delay_cycles` | no | `0` | Prepended `req=0` cycles before first pattern. |
| `patterns` | no | absent | If present, this list drives generation. |

Precedence/exclusivity:
- Master format is effectively either:
  - flat single-pattern master (no `patterns`)
  - or `patterns` list.
- If `patterns` exists, flat pattern fields at master level are ignored for traffic generation (except master-level fields like `start_delay_cycles`).

### Common Pattern Fields (apply to every pattern type)
| Field | Required | Default | Notes |
|---|---|---|---|
| `mem_access_type` | yes | none | Pattern selector. |
| `description` | no | empty | Label used in reports. |
| `job` | no | `"default"` | Dependency graph node name. |
| `wait_for_jobs` | no | `[]` | Inserts dependency gate before pattern. |
| `n_transactions` | conditional | derivable for many patterns | If omitted, derived when supported. |
| `traffic_pct` | no | `100` | Adds per-request idle shaping (`req=0`) on patterns that implement traffic shaping. |

## Pattern Catalog
The tables below list pattern-specific fields.  
Complete field set for a pattern = **common fields above + pattern-specific fields below**.
`Required = conditional` means: required unless the documented derivation path is present.

### `idle`
No memory transaction. Emits idle and trailing `PAUSE`.

Pattern-specific fields: none.

### `random`
Uniform random over a region.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `n_transactions` | yes | none | int | Not derivable for this pattern. |
| `region_base_address` | no | evenly partitioned per master | address (bytes) | |
| `region_size_bytes` | no | evenly partitioned per master | bytes | |
| `traffic_read_pct` | no | random R/W mix | % | If set, deterministic read/write split. |

### `linear`
1D strided stream.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `n_transactions` | conditional | derived | int | Derivable from `length` or `region_size_bytes`. |
| `length` | no | none | int | Alias source for derived `n_transactions`. |
| `start_address` | no | `"0"` | address (bytes) | If absent and `region_base_address` exists, uses `region_base_address`. |
| `stride0` | no | `0` (or `1` if `region_size_bytes` set) | words | |
| `region_base_address` | no | evenly partitioned per master | address (bytes) | Used for region context and start fallback. |
| `region_size_bytes` | no | evenly partitioned per master | bytes | Can derive `n_transactions`. |
| `traffic_read_pct` | no | random R/W mix | % | |

### `2d`
2D walk.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `n_transactions` | conditional | derived | int | Derivable from `len_d0 * len_d1`. |
| `start_address` | no | `"0"` | address (bytes) | |
| `stride0` | no | `0` | words | |
| `len_d0` | conditional | none | int | |
| `stride1` | no | `0` | words | |
| `len_d1` | conditional | none | int | |
| `idle_cycles_between_phases` | no | `0` | cycles | Inserts explicit boundary idles. |

### `3d`
3D walk.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `n_transactions` | conditional | derived | int | Derivable from `len_d0 * len_d1 * len_d2`. |
| `start_address` | no | `"0"` | address (bytes) | |
| `stride0` | no | `0` | words | |
| `len_d0` | conditional | none | int | |
| `stride1` | no | `0` | words | |
| `len_d1` | conditional | none | int | |
| `stride2` | no | `0` | words | |
| `len_d2` | conditional | none | int | |
| `idle_cycles_between_phases` | no | `0` | cycles | Inserts explicit boundary idles. |

### `matmul_phased` (alias: `matmul`)
Phased A-read / B-read / C-write traffic.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `n_transactions` | conditional | derived | int | Derivable from region size or matrix dims. |
| `region_base_address`, `region_size_bytes` | conditional | evenly partitioned | bytes | Combined region (auto A/B/C split). |
| `matrix_m`, `matrix_n`, `matrix_k` | no | none | int | Alternative source for derived `n_transactions`. |
| `region_base_address_a/b/c`, `region_size_bytes_a/b/c` | no | none | bytes | Explicit per-phase regions. |
| `matmul_ratio_a/b/c` | no | `1/1/1` | relative weights | |
| `idle_cycles_between_phases` | no | `0` | cycles | Inserts explicit phase-boundary idles. |

Mutual exclusivity / precedence:
- If explicit `*_a/b/c` regions are provided, they take precedence over combined-region auto-split.

### `multi_linear`
Multiple subregions, schedule-driven interleave.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `regions` | yes | none | array | Each entry has `base`, `size_bytes`, optional `stride_words`, `read_pct`. |
| `schedule` | no | `round_robin` | string | |
| `burst_len` | no | `1` | int | |
| `n_transactions` | conditional | derived | int | Derivable from sum of region sizes. |

### `bank_group_linear`
Linear stream constrained by bank group phase controls.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `start_bank` | yes | none | int | 0-based bank index. |
| `bank_group_span` | yes | none | int | Number of banks in active group. |
| `stride_beats` | no | `1` | beats | |
| `bank_group_hop` | no | `0` | int | Group-phase hop per wrap. |
| `wen` | no | mixed R/W | `0` or `1` | Fixed direction if set. |
| `n_transactions` | yes | none | int | Required for this pattern. |

### `rw_rowwise`
Per-row read phase then write phase.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `row_base_address` | yes | none | address (bytes) | |
| `row_size_bytes` | yes | none | bytes | |
| `n_rows` | yes | none | int | |
| `row_stride_bytes` | yes | none | bytes | |
| `reads_per_row` | yes | none | int | |
| `writes_per_row` | yes | none | int | |
| `idle_cycles_between_rows` | no | `0` | cycles | Inserts explicit row-boundary idles. |
| `n_transactions` | conditional | derived | int | Derivable as `n_rows * (reads_per_row + writes_per_row)`. |

### `gather_scatter`
Gather from multiple read regions, scatter to write region.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `read_regions` | yes | none | array | Each entry: `base`, `size_bytes`. |
| `write_region` | yes | none | object | `base`, `size_bytes`. |
| `chunk_bytes` | no | transaction width | bytes | Address increment granularity. |
| `schedule` | no | `4read_1write` | string | |
| `n_transactions` | conditional | derived | int | Derivable from region sizes and chunk. |

### `matmul_tiled_interleave` (alias: `matmul_tiled`)
Tile-like interleaving among A/B/C streams.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `region_base_address`, `region_size_bytes` | no | evenly partitioned | bytes | Used as fallback context for auto split when explicit A/B/C are absent. |
| `region_base_address_a/b/c`, `region_size_bytes_a/b/c` | conditional | fallback split | bytes | Preferred explicit mode. |
| `tile_a_bytes`, `tile_b_bytes`, `tile_c_bytes` | no | transaction width | bytes | Tile step payloads per stream. |
| `tiles` | no | `1` | int | |
| `ab_c_schedule` | no | `A_B_C` | string | |
| `idle_cycles_between_tiles` | no | `0` | cycles | Inserts explicit tile-boundary idles. |
| `n_transactions` | conditional | derived | int | Can be derived from tile parameters/schedule. |

Mutual exclusivity / precedence:
- Preferred: explicit A/B/C regions.
- If missing, generator falls back to splitting combined region context.

### `hotspot_random`
Weighted random traffic across hot regions.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `hot_regions` | yes | none | array | Each entry: `base`, `size_bytes`, optional `weight` (default `1`). |
| `n_transactions` | no | weak fallback | int | Prefer setting explicitly. |
| `traffic_read_pct` | no | random R/W mix | % | |

## All Sources of `req=0` Cycles
`req=0` can be generated by:

1. `traffic_pct` shaping
- For every emitted request, inserts `idles_per_req = round((100-pct)/pct)` idle lines.
- Applies in random/linear and all new patterns that support `traffic_pct`.

2. Boundary idle knobs (JSON)
- `idle_cycles_between_phases` in `2d`, `3d`, `matmul_phased`
- `idle_cycles_between_rows` in `rw_rowwise`
- `idle_cycles_between_tiles` in `matmul_tiled_interleave`

3. `start_delay_cycles` (per master)
- Prepends idle lines before first pattern.

4. Dependency gate for `wait_for_jobs`
- For each dependent pattern, generator inserts a synthetic idle+`PAUSE` gate before real traffic.

5. `idle` pattern
- Explicitly emits idle and `PAUSE`.

## Read/Write Blocked-Set Functionality
Address filtering is implemented inside pattern generators via:
- `_is_allowed(add, wen, read_blocked_set, write_blocked_set)`
- `_record_access(add, wen, read_blocked_set, write_blocked_set)`

Behavior (within one pattern invocation):
- Read checks (`wen=1`) consult `read_blocked_set`.
- Write checks (`wen=0`) consult `write_blocked_set`.
- On every emitted access, the address is added to `write_blocked_set`.
- On emitted writes only, the address is also added to `read_blocked_set`.

Effective policy:
- read after read: allowed
- write after read: blocked
- read after write: blocked
- write after write: blocked

Notes:
- Blocking state is pattern-local (it does not persist across patterns).
- Generators are strict about transaction count: each non-idle pattern must emit exactly `n_transactions` (`N_TEST`).
- If blocking rules make the requested count unreachable for a pattern, generation fails with an explicit error instead of silently under-emitting.

## Outputs

### 1. Stimuli vectors
Path:
- `target/verif/simvectors/generated/stimuli/master_log_<i>.txt`
- `target/verif/simvectors/generated/stimuli/master_hwpe_<i>.txt`

Per-cycle vector line format:
- `req id wen data add`
- `req`: `1` active request, `0` idle
- `id`: request ID (`IW` bits)
- `wen`: `1` read, `0` write
- `data`: payload (`DATA_WIDTH` bits for narrow, `HWPE_WIDTH_FACT*DATA_WIDTH` for wide)
- `add`: byte address (`ADD_WIDTH` bits)

Fence token:
- A standalone line `PAUSE` is emitted at end of each pattern segment.

### 2. Memory map report
Path:
- `target/verif/simvectors/generated/memory_map.txt`

Contains:
- per-pattern region and traffic summary
- dependency/fence map
- temporal schedule summary
- region lifetimes and overlaps context

### 3. Dataflow visualization
Path:
- `target/verif/simvectors/generated/dataflow.html`

Contains:
- execution timeline (SVG)
- region-map blocks
- per-region usage cards
- overlap table

### 4. Optional outputs
- `--golden`: emits expected read-data vectors under `generated/golden/`
- `--emit_phases_mk <path>`: emits fence/dependency Makefile fragment

## Recommended Extra Documentation
- one minimal JSON example per pattern
- exact dependency semantics for `job` / `wait_for_jobs` with 2-3 pattern chain examples
- known caveat: timeline model in report is simplified and may differ from full RTL contention timing
