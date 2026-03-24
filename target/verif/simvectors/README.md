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
| `trailing_bytes` / `trailing_bytes_a/b/c` | integer | Partial-beat byte count for last transaction. `0` = full beat (default). Only `matmul_phased` auto-derives this from matrix dims; other patterns use `0` unless explicitly passed. |

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

### `matmul_phased`
Phased A-read / B-read / C-write traffic.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `n_transactions` | conditional | derived | int | Derivable from region size or matrix dims. When set explicitly, all beats are assumed full-width (no trailing partial beat). |
| `region_base_address`, `region_size_bytes` | conditional | evenly partitioned | bytes | Combined region (auto A/B/C split). |
| `matrix_m`, `matrix_n`, `matrix_k` | conditional | none | int | Derive `n_transactions` in bus beats. Requires `matrix_elem_bytes`. |
| `matrix_elem_bytes` | conditional | — | bytes | Element size in bytes for all operands (1=int8, 2=fp16/bf16, 4=fp32/int32). **Required** when deriving `n_transactions` from `matrix_m/n/k`. Overridden per-operand by `matrix_elem_bytes_a/b/c`. |
| `matrix_elem_bytes_a/b/c` | no | `matrix_elem_bytes` | bytes | Per-operand element size override. Useful for mixed-precision (e.g. A/B=fp8, C=fp32). |
| `region_base_address_a/b/c`, `region_size_bytes_a/b/c` | no | none | bytes | Explicit per-phase regions. |
| `matmul_ratio_a/b/c` | no | `1/1/1` | relative weights (bus beats) | Ignored when `matrix_m/n/k` are present (ratios are auto-derived in beat units). |
| `idle_cycles_between_phases` | no | `0` | cycles | Inserts explicit phase-boundary idles. |

Mutual exclusivity / precedence:
- If explicit `*_a/b/c` regions are provided, they take precedence over combined-region auto-split.
- If `matrix_m/n/k` are present: `matrix_elem_bytes` is required. `n_transactions` and `matmul_ratio_a/b/c` are both derived automatically in bus-beat units, and trailing partial beats are computed and emitted. JSON-provided `matmul_ratio_a/b/c` are ignored.
- If `n_transactions` is explicit (no matrix dims): all beats are full-width (`be` all-ones). This is correct when region sizes were already specified in bus-beat units.

**Bus-beat unit requirement**: `n_transactions`, `matmul_ratio_a/b/c`, and `region_size_bytes_a/b/c` must all be expressed in bus beats (one beat = `DATA_WIDTH/8` bytes for the master). For int8 tensors on a 256-bit (32-byte) HWPE, one beat covers 32 elements. Mixing element-count units and beat-count units causes wrap-around errors.

**Preflight check**: main.py verifies that each phase's transaction count fits within its region (no wrap-around). If not, generation fails with an explicit error.

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

**Log masters only.** This pattern targets individual bank words (`WIDTH_OF_MEMORY_BYTE` granularity) and cannot be used with wide-bus HWPE masters. Generation fails with an explicit error if called from an HWPE master.

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

### `matmul_tiled_interleave`
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

### `copy_linear`
Interleaved read-from-src / write-to-dst streaming copy. Models a streaming copy or pack engine (e.g. DataMover doing im2col/pack): alternates `read[src_i]` / `write[dst_i]` pairs. Always 50% R / 50% W. `n_transactions` must be even (`n_copy_ops * 2`).

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `src_base_address` | yes | none | address (bytes) | Source region start. |
| `src_size_bytes` | yes | none | bytes | Source region size. Wraps on exhaustion. |
| `dst_base_address` | yes | none | address (bytes) | Destination region start. |
| `dst_size_bytes` | yes | none | bytes | Destination region size. Wraps on exhaustion. |
| `n_transactions` | conditional | derived | int | Derived as `2 * (src_size_bytes / access_bytes)` if omitted. |
| `traffic_pct` | no | `100` | % | Idle shaping between transactions. |

### `hotspot_random`
Weighted random traffic across hot regions.

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `hot_regions` | yes | none | array | Each entry: `base`, `size_bytes`, optional `weight` (default `1`). |
| `n_transactions` | no | weak fallback | int | Prefer setting explicitly. |
| `traffic_read_pct` | no | random R/W mix | % | |

### `depthwise_windowed`
Structured depthwise-convolution traffic pattern. For each channel group: optional compact kernel-bank reads, then for each output point reads `KH*KW` input-window elements, then writes output beats. Padding is modeled by skipping out-of-bounds reads (no transaction emitted).

| Field | Required | Default | Format / unit | Notes |
|---|---|---|---|---|
| `input_base_address` | yes | none | address (bytes) | |
| `input_row_stride_bytes` | yes | none | bytes | Row stride in input feature map. |
| `input_channel_stride_bytes` | yes | none | bytes | Channel stride in input feature map. |
| `weight_base_address` | yes | none | address (bytes) | |
| `weight_channel_stride_bytes` | yes | none | bytes | Channel stride in weight bank. |
| `output_base_address` | yes | none | address (bytes) | |
| `output_row_stride_bytes` | yes | none | bytes | Row stride in output feature map. |
| `output_channel_stride_bytes` | yes | none | bytes | Channel stride in output feature map. |
| `out_h` | yes | none | int | Output spatial height. |
| `out_w` | yes | none | int | Output spatial width. |
| `channels` | yes | none | int | Total number of channels. |
| `kernel_h` | no | `3` | int | Kernel height. |
| `kernel_w` | no | `3` | int | Kernel width. |
| `stride_h` | no | `1` | int | Convolution stride (H). |
| `stride_w` | no | `1` | int | Convolution stride (W). |
| `pad_h` | no | `0` | int | Zero-padding (H). |
| `pad_w` | no | `0` | int | Zero-padding (W). |
| `channel_group` | no | `1` | int | Channels processed per group pass. |
| `include_weights` | no | `true` | bool | If false, omits kernel-bank reads. |
| `output_writes_per_point` | no | `1` | int | Write beats emitted per output spatial point. |
| `idle_cycles_between_rows` | no | `0` | cycles | Idles inserted between output rows. |
| `idle_cycles_between_groups` | no | `0` | cycles | Idles inserted between channel groups. |
| `n_transactions` | conditional | derived | int | Prefer setting explicitly; derivation depends on padding/blocking. |

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
- Each gate crossing increments the driver's `fence_idx` counter. The required `fence_idx` values are packed into `LEVEL_BITS`-bit fields in `FENCE_REQ_LEVELS_PACKED`.
- `LEVEL_BITS` is auto-derived by main.py as the minimum bits to represent the maximum required `fence_idx` in the workload (`max_req_level.bit_length()`), and emitted to `fence_params.svh`. Both the packed field width and the fence array depth (`2^LEVEL_BITS`) are derived from it, so they always match the workload with no manual configuration.

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
- write after read: blocked (exception: `rw_rowwise`, see below)
- read after write: blocked
- write after write: blocked

Notes:
- Blocking state is pattern-local (it does not persist across patterns).
- Generators are strict about transaction count: each non-idle pattern must emit exactly `n_transactions` (`N_TEST`).
- If blocking rules make the requested count unreachable for a pattern, generation fails with an explicit error instead of silently under-emitting.
- **`rw_rowwise` exception**: the reads phase does not call `_record_access`, so subsequent writes to the same addresses are not blocked. This is intentional — `rw_rowwise` is an explicit read-modify-write pattern where reads and writes target the same address range by design.

## Outputs

### 1. Stimuli vectors
Path:
- `target/verif/simvectors/generated/stimuli/master_log_<i>.txt`
- `target/verif/simvectors/generated/stimuli/master_hwpe_<i>.txt`

Per-cycle vector line format:
- `req id wen be data add`
- `req`: `1` active request, `0` idle
- `id`: request ID (`IW` bits)
- `wen`: `1` read, `0` write
- `be`: byte-enable mask (`DATA_WIDTH/8` bits, one bit per byte lane). All-ones for full beats. For the trailing beat of a transfer whose total size is not a multiple of `DATA_WIDTH/8`, bits `[valid_bytes-1:0]` are set and the rest are zero. On reads (`wen=1`) `be` is driven for documentation/tracing; the memory subsystem typically ignores `be` on reads.
- `data`: payload (`DATA_WIDTH` bits for narrow, `HWPE_WIDTH_FACT*DATA_WIDTH` for wide)
- `add`: byte address (`ADD_WIDTH` bits)

**Trailing beat support**: patterns accept a `trailing_bytes` parameter (per-phase `trailing_bytes_a/b/c` for `matmul_phased`). When `>0`, the last emitted transaction of that phase/pattern carries a partial `be`. For all patterns other than `matmul_phased`, `trailing_bytes` defaults to `0` (all beats full). For `matmul_phased` with `matrix_m/n/k`, trailing bytes are computed automatically from `(M*K*elem_bytes_a) % access_bytes` etc.

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
- **Execution timeline** (SVG Gantt): one row per driver, one box per pattern, colored by driver. Text in boxes is clipped to the box width but may extend into empty space that follows.
- **Memory address timeline** (SVG): address (Y) × transaction number (X). Background bands show each named region proportional to its TCDM footprint (minimum 14 px per region). Colored rectangles show read/write accesses per pattern. Y axis always spans the full TCDM address range with accurate hex labels at each region start.
- **Job dependency DAG**: nodes colored by driver, Bezier edges for `wait_for_jobs` dependencies. Nodes are level-assigned by topological longest-path and sorted by driver within each level.
- **Legend**: read / write / read+write color key.

### 4. Optional outputs
- `--golden`: emits expected read-data vectors under `generated/golden/`
- `--emit_fence_svh <path>`: override output path for `fence_params.svh` (default: `generated/fence_params.svh`)

## Recommended Extra Documentation
- one minimal JSON example per pattern
- exact dependency semantics for `job` / `wait_for_jobs` with 2-3 pattern chain examples
- known caveat: timeline model in report is simplified and may differ from full RTL contention timing
