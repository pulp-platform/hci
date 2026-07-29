# `hci-tracer` — transaction log comparison

`hci-tracer` compares the transaction logs written in simulation by the
`hci_transaction_tracer` (`rtl/common/hci_transaction_tracer.sv`) and
`hwpe_stream_transaction_tracer` (`hwpe-stream/rtl/hwpe_stream_transaction_tracer.sv`)
modules.

**Only the content of valid data is compared — never the time.** A transaction
enters a log only when its handshake was satisfied (`req & gnt` for HCI requests,
`r_valid & r_ready` for HCI responses, `valid & ready` for a HWPE-Stream beat),
and the `cycle` field is carried through and reported purely so a difference can
be found in a waveform. Two datapaths with wildly different timing that move the
same bytes compare equal.

## Build and test

```sh
cargo build --release          # target/release/hci-tracer
cargo test                     # unit + integration tests
```

Dependencies are `serde`, `serde_json`, `clap` and `owo-colors`; `--offline`
works if the crates are already in the local registry.

The crate is edition 2021 and builds with **Rust 1.81 or newer**, which is what
`rust-version` in `Cargo.toml` declares. Two things keep it that way, and both
matter if you touch the dependencies:

* `clap` is capped below 4.6 (`~4.5`). clap 4.6 and its `clap_lex` are written in
  edition 2024 and need Rust 1.85, which fails on an older toolchain with
  `feature `edition2024` is required`.
* `resolver = "3"` makes Cargo pick dependency versions compatible with the
  declared `rust-version` rather than the newest ones. It needs Cargo 1.84+.

`Cargo.lock` is committed, so a plain `cargo build` uses a known-good set
regardless. If you bump a dependency, re-check with an old toolchain:

```sh
rustup toolchain install 1.81 --profile minimal
cargo +1.81 test
```

## Usage

```
hci-tracer hci-vs-hci        --a-req F --a-rsp F --b-req F --b-rsp F
hci-tracer hci-req-vs-stream --hci F --stream F
hci-tracer hci-rsp-vs-stream --hci F --stream F
hci-tracer stream-vs-stream  --a F --b F
hci-tracer show              F
```

`hci-vs-hci` takes a request pair, a response pair, or both; each pair must be
given together, and it diffs the two streams independently, reporting one section
each plus a combined verdict.

`hci-req-vs-stream` compares only the **write** requests of the HCI log against
the stream. Mind the HCI polarity: `wen = 1` is a LOAD and `wen = 0` is a STORE,
so "write enable asserted" means `wen == 0`. Read requests are dropped, with a
note saying how many.

### What counts as content

| mode | compared by default |
|---|---|
| HCI request vs HCI request | `add`, `wen`, `be`, `data` masked by `be` |
| HCI response vs HCI response | `r_data`, `r_opc` |
| HCI write requests vs HWPE-Stream | `be`/`strb` as enabled bits, `data` masked by them |
| HCI response vs HWPE-Stream | `r_data` vs `data`, masked by the stream's `strb` |
| HWPE-Stream vs HWPE-Stream | `strb`, `data` masked by `strb` |

Never compared: `cycle` and `seq`. Off by default: `user`/`r_user`, `id`/`r_id`,
`ecc`/`r_ecc` — switch them on with `--check-user`, `--check-id`, `--check-ecc`.

Older HCI-Core interfaces have fewer side channels than current ones: a log whose
header declares `IW = 0` or `EW = 0` carries no `id` or `ecc` fields at all. Those
are left out of the comparison, so a trace taken on an old interface diffs cleanly
against one taken on a new interface. Asking for a side channel that a log does not
carry is refused outright rather than compared against a stub value, which would
report a difference for every transaction.

Byte enables are canonicalized to a bit-level mask before being compared, so
`be = 0xf` with `BW = 8` is *equal* to `strb = 0xff` with `ELEMENT_WIDTH = 4` on a
32-bit bus: both describe the same 32 enabled data bits. Bytes that neither side
considers meaningful are don't-care; `--strict-be` compares full data words
instead, and `--ignore-en` keeps the masking but stops comparing the encodings.

### Differing data widths

Refused by default, since silently repacking a wide beat into narrow ones is a
good way to hide a packing bug:

```
error: data width mismatch: A (HCI request, DW=64 ...) vs B (HWPE-Stream, DATA_WIDTH=32 ...)
  hint: pass --split to compare each wide beat as several narrow ones
```

`--split` (or `--split=N` to pin the ratio) splits the wider side in
**little-endian element order** — sub-beat 0 carries the low bits — slicing
`be`/`strb` with it and advancing `add` per sub-beat. Split beats are labelled
`#0042.1`.

### x/z values

Unknown bits are parsed, not rejected. Inside a `be`/`strb`-disabled byte they
are erased by the masking and are a genuine don't-care. Inside an *enabled* byte
they are a difference by default (`--x-policy=mismatch`), since HCI RTL is not
supposed to drive X on a live bus; `--x-policy=match` treats them as wildcards
and `--x-policy=error` aborts.

### Truncated logs

The tracers close the JSON array from a SystemVerilog `final` block, which does
not run if the simulation is killed. Such a log is cut back to its last complete
transaction and repaired automatically, with a warning saying how much was lost.
`--repair=never` surfaces the parse error instead; `--fail-on-truncated` makes a
repair an exit-4 failure.

### Other options

```
--color auto|always|never   --ascii            --context N (default 2)
--max-report N (default 50) --summary-only     -q  -v
--ignore-add  --ignore-wen  --drop-empty       --max-diff N (default 2000)
```

`--max-diff` bounds the edit distance searched exactly. Beyond it the two logs
are considered unrelated and compared position by position, with a warning —
this is what keeps the tool from grinding on two completely different traces.

### Exit status

| code | meaning |
|---|---|
| 0 | the logs carry the same content |
| 1 | differences were found |
| 2 | usage, I/O or schema error |
| 4 | an input was truncated and `--fail-on-truncated` was given |

## Reading the output

```
  x  #0004  value mismatch
       A seq=4 cycle=18        B seq=4 cycle=45
       add      0x1c01_0010                 0x1c01_0010
       be       0xf                         0xf
       data&be  0xdead_4444                 0xdead_4044
                        ^                           ^
```

Differing nibbles are painted red on both sides; the caret row appears only when
colour is off. `-` / `+` gutters mark transactions present on one side only, `=`
marks matching context. Values wider than 64 bits are folded into 64-bit rows
labelled by bit range, with runs of identical rows elided unless `-v` is given.

## Log format

Each log is one JSON document: a `schema` tag, the `interface` parameters, the
`path` of the tracer instance, and a `transactions` array. See
`hci_request.schema.json`, `hci_response.schema.json` and
`../hwpe-stream/tracer/hwpe_stream_transaction.schema.json`.

```json
{
  "schema": "hci_transaction_request-v1",
  "interface": { "DW": 32, "AW": 32, "BW": 8, "UW": 0, "IW": 8, "EW": 0 },
  "path": "tb.i_tracer_a",
  "transactions": [
    { "seq": 0, "cycle": 10, "add": "0x1c010000", "wen": 0,
      "data": "0xdead0000", "be": "0xf", "id": "0x00" }
  ]
}
```

Hexadecimal fields tolerate a `0x` or `<size>'h` prefix, `_` separators, upper
case, and `x`/`z` nibbles. Side channels are present only when their width
parameter is non-zero.

The synthetic logs used by the integration tests live in `tests/fixtures/` and
are regenerated by `python3 tests/fixtures/gen_fixtures.py`.
