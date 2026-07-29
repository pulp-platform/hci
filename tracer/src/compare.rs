// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! What counts as the *content* of a transaction.
//!
//! Two notions are kept apart on purpose:
//!
//! * the **key** ([`key_of`]) is an independent, hashable summary of a beat,
//!   used only to *align* the two sequences in [`crate::diff`]. It must be an
//!   equivalence relation, so it cannot depend on the beat it is compared with.
//! * the **verdict** ([`beats_equal`]) is the authority on whether an aligned
//!   pair actually matches. It may use both beats, which is what allows an HCI
//!   response to be compared against a partially strobed HWPE-Stream beat, and
//!   what makes `--x-policy=match` possible.
//!
//! The verdict is always a *relaxation* of key equality, so equal keys imply a
//! match and the reporting pass can only ever downgrade a mismatch to a match.

use std::path::Path;

use crate::error::{Error, Result};
use crate::model::{Beat, LoadedLog, LogKind, Payload};
use crate::value::Value;

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Mode {
    /// Two HCI request logs.
    HciReq,
    /// Two HCI response logs.
    HciRsp,
    /// HCI write requests (`wen == 0`) against a HWPE-Stream.
    ReqVsStream,
    /// HCI responses against a HWPE-Stream.
    RspVsStream,
    /// Two HWPE-Stream logs.
    StreamVsStream,
}

impl Mode {
    pub fn label(self) -> &'static str {
        match self {
            Mode::HciReq => "HCI request",
            Mode::HciRsp => "HCI response",
            Mode::ReqVsStream => "HCI write requests vs HWPE-Stream",
            Mode::RspVsStream => "HCI responses vs HWPE-Stream",
            Mode::StreamVsStream => "HWPE-Stream",
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum XPolicy {
    /// An x/z bit in an enabled byte matches anything.
    Match,
    /// An x/z bit in an enabled byte is a difference (default).
    Mismatch,
    /// An x/z bit in an enabled byte aborts the run.
    Error,
}

#[derive(Debug, Clone)]
pub struct CompareOptions {
    /// Compare full data words, without `be`/`strb` masking.
    pub strict_be: bool,
    pub check_user: bool,
    pub check_id: bool,
    pub check_ecc: bool,
    pub ignore_add: bool,
    pub ignore_wen: bool,
    /// Drop `be`/`strb` from the key, but keep using them to mask data.
    pub ignore_en: bool,
    pub x: XPolicy,
}

impl Default for CompareOptions {
    fn default() -> Self {
        CompareOptions {
            strict_be: false,
            check_user: false,
            check_id: false,
            check_ecc: false,
            ignore_add: false,
            ignore_wen: false,
            ignore_en: false,
            x: XPolicy::Mismatch,
        }
    }
}

/// Which fields take part in the comparison, for one particular mode.
#[derive(Debug, Copy, Clone)]
pub struct KeySpec {
    pub add: bool,
    pub wen: bool,
    pub en: bool,
    pub opc: bool,
    pub user: bool,
    pub id: bool,
    pub ecc: bool,
    /// Mask data with the beat's own enable when building the *key*.
    pub mask_key_data: bool,
}

/// Everything needed to compare two particular logs.
#[derive(Debug, Clone)]
pub struct CmpCtx {
    pub mode: Mode,
    pub spec: KeySpec,
    pub opts: CompareOptions,
    /// Common data width, after `--split` normalization.
    pub data_width: u32,
    /// Bits per enable bit on each side (`BW` / `ELEMENT_WIDTH`).
    pub elem_bits_a: u32,
    pub elem_bits_b: u32,
    /// Label used for the data row of the report, e.g. `data&be`.
    pub data_label: String,
}

impl CmpCtx {
    pub fn new(mode: Mode, a: &LoadedLog, b: &LoadedLog, data_width: u32, opts: CompareOptions) -> CmpCtx {
        let masking = !opts.strict_be;
        let spec = match mode {
            Mode::HciReq => KeySpec {
                add: !opts.ignore_add,
                wen: !opts.ignore_wen,
                en: !opts.ignore_en,
                opc: false,
                user: opts.check_user,
                id: opts.check_id,
                ecc: opts.check_ecc,
                mask_key_data: masking,
            },
            Mode::HciRsp => KeySpec {
                add: false,
                wen: false,
                en: false,
                opc: true,
                user: opts.check_user,
                id: opts.check_id,
                ecc: opts.check_ecc,
                // Responses carry no enable, so there is nothing to mask with.
                mask_key_data: false,
            },
            Mode::ReqVsStream | Mode::StreamVsStream => KeySpec {
                add: false,
                wen: false,
                en: !opts.ignore_en,
                opc: false,
                user: false,
                id: false,
                ecc: false,
                mask_key_data: masking,
            },
            Mode::RspVsStream => KeySpec {
                add: false,
                wen: false,
                en: false,
                opc: false,
                user: false,
                id: false,
                ecc: false,
                // Only one side has an enable: aligning on raw data and letting
                // `beats_equal` apply the stream's `strb` keeps the alignment
                // sound while still honouring the don't-care bytes.
                mask_key_data: false,
            },
        };

        let data_label = {
            let base = if a.kind == LogKind::HciResponse && b.kind == LogKind::HciResponse {
                "r_data"
            } else {
                "data"
            };
            let has_en = a.beats.first().map_or(true, |x| x.payload.enable().is_some())
                || b.beats.first().map_or(true, |x| x.payload.enable().is_some());
            if masking && has_en {
                match (a.kind, b.kind) {
                    (LogKind::HciRequest, LogKind::HciRequest) => "data&be".to_string(),
                    (LogKind::HwpeStream, LogKind::HwpeStream) => "data&strb".to_string(),
                    _ => format!("{base}&en"),
                }
            } else {
                base.to_string()
            }
        };

        CmpCtx {
            mode,
            spec,
            opts,
            data_width,
            elem_bits_a: a.iface.elem_bits(),
            elem_bits_b: b.iface.elem_bits(),
            data_label,
        }
    }

    fn elem_bits(&self, side: Side) -> u32 {
        match side {
            Side::A => self.elem_bits_a,
            Side::B => self.elem_bits_b,
        }
    }

    /// Names of the fields that take part in the comparison, for the header.
    pub fn key_names(&self) -> Vec<String> {
        let mut v = Vec::new();
        if self.spec.add {
            v.push("add".to_string());
        }
        if self.spec.wen {
            v.push("wen".to_string());
        }
        if self.spec.en {
            v.push(self.en_label());
        }
        v.push(self.data_label.clone());
        if self.spec.opc {
            v.push("r_opc".to_string());
        }
        for (on, name) in [
            (self.spec.user, "user"),
            (self.spec.id, "id"),
            (self.spec.ecc, "ecc"),
        ] {
            if on {
                v.push(name.to_string());
            }
        }
        v
    }

    /// Fields that are deliberately left out.
    pub fn ignored_names(&self) -> Vec<String> {
        let mut v = vec!["cycle".to_string(), "seq".to_string()];
        for (on, name) in [
            (self.spec.user, "user"),
            (self.spec.id, "id"),
            (self.spec.ecc, "ecc"),
        ] {
            if !on {
                v.push(name.to_string());
            }
        }
        if !self.spec.add && self.mode == Mode::HciReq {
            v.push("add".to_string());
        }
        v
    }

    fn en_label(&self) -> String {
        match self.mode {
            Mode::HciReq => "be".to_string(),
            Mode::StreamVsStream => "strb".to_string(),
            _ => "en".to_string(),
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Side {
    A,
    B,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct KeyField {
    pub name: &'static str,
    pub val: Value,
}

/// Alignment key: derived from [`Payload`] only, never from `seq`/`cycle`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Key(pub Vec<KeyField>);

/// Expanded bit-level enable of a beat, or all-ones when the domain has none.
fn enable_mask(beat: &Beat, elem_bits: u32, width: u32) -> Value {
    match beat.payload.enable() {
        Some(en) => en.expand_enable(elem_bits, width).unwrap_or_else(|_| Value::ones(width)),
        None => Value::ones(width),
    }
}

pub fn key_of(beat: &Beat, side: Side, ctx: &CmpCtx) -> Key {
    let width = ctx.data_width;
    let elem_bits = ctx.elem_bits(side);
    let mask = enable_mask(beat, elem_bits, width);
    let mut fields = Vec::new();

    match &beat.payload {
        Payload::Req { add, wen, data, user, id, ecc, .. } => {
            if ctx.spec.add {
                fields.push(KeyField { name: "add", val: add.clone() });
            }
            if ctx.spec.wen {
                fields.push(KeyField {
                    name: "wen",
                    val: Value::from_u64(*wen as u64, 1),
                });
            }
            if ctx.spec.en {
                fields.push(KeyField { name: "en", val: mask.clone() });
            }
            fields.push(KeyField {
                name: "data",
                val: masked_data(data, &mask, width, ctx.spec.mask_key_data),
            });
            push_side_channels(&mut fields, ctx, user, id, ecc);
        }
        Payload::Rsp { r_data, r_opc, r_user, r_id, r_ecc } => {
            if ctx.spec.en {
                fields.push(KeyField { name: "en", val: mask.clone() });
            }
            fields.push(KeyField {
                name: "data",
                val: masked_data(r_data, &mask, width, ctx.spec.mask_key_data),
            });
            if ctx.spec.opc {
                fields.push(KeyField { name: "r_opc", val: Value::from_u64(*r_opc as u64, 1) });
            }
            push_side_channels(&mut fields, ctx, r_user, r_id, r_ecc);
        }
        Payload::Str { data, .. } => {
            if ctx.spec.en {
                fields.push(KeyField { name: "en", val: mask.clone() });
            }
            fields.push(KeyField {
                name: "data",
                val: masked_data(data, &mask, width, ctx.spec.mask_key_data),
            });
            // A stream has no side channels; when they are requested the other
            // side's values simply have nothing to be compared against, which
            // the mode set-up already rules out.
        }
    }
    Key(fields)
}

fn masked_data(data: &Value, mask: &Value, width: u32, mask_it: bool) -> Value {
    let d = if data.width() == width { data.clone() } else { data.resize(width) };
    if mask_it {
        d.mask_with(mask)
    } else {
        d
    }
}

fn push_side_channels(
    fields: &mut Vec<KeyField>,
    ctx: &CmpCtx,
    user: &Option<Value>,
    id: &Option<Value>,
    ecc: &Option<Value>,
) {
    for (on, name, v) in [
        (ctx.spec.user, "user", user),
        (ctx.spec.id, "id", id),
        (ctx.spec.ecc, "ecc", ecc),
    ] {
        if on {
            fields.push(KeyField {
                name,
                val: v.clone().unwrap_or_else(|| Value::zeros(1)),
            });
        }
    }
}

/// The authoritative verdict for an aligned pair.
pub fn beats_equal(a: &Beat, b: &Beat, ctx: &CmpCtx) -> bool {
    rows_of(a, b, ctx).iter().all(|r| !r.differs)
}

/// One line of the difference report.
#[derive(Debug, Clone)]
pub struct FieldRow {
    pub name: String,
    pub a: Cell,
    pub b: Cell,
    pub differs: bool,
}

#[derive(Debug, Clone)]
pub enum Cell {
    Val(Value),
    Text(String),
    /// The field does not exist on this side (cross-domain comparison).
    Missing,
}

/// Compared fields of an aligned pair, with the per-field verdict.
///
/// This is both the reporting view and, through [`beats_equal`], the definition
/// of "these two transactions carry the same content".
pub fn rows_of(a: &Beat, b: &Beat, ctx: &CmpCtx) -> Vec<FieldRow> {
    let width = ctx.data_width;
    let mask_a = enable_mask(a, ctx.elem_bits_a, width);
    let mask_b = enable_mask(b, ctx.elem_bits_b, width);
    let mut rows = Vec::new();

    if ctx.spec.add {
        let (va, vb) = (payload_add(a), payload_add(b));
        rows.push(row("add", va, vb));
    }
    if ctx.spec.wen {
        let (wa, wb) = (payload_wen(a), payload_wen(b));
        rows.push(FieldRow {
            name: "wen".to_string(),
            a: wen_cell(wa),
            b: wen_cell(wb),
            differs: wa != wb,
        });
    }
    if ctx.spec.en {
        // Show the raw `be`/`strb` as the tracer logged it, but decide on the
        // canonicalized bit masks, so that two different encodings of the same
        // enabled bits are not reported as a difference.
        rows.push(FieldRow {
            name: ctx.en_label(),
            a: cell_of(a.payload.enable()),
            b: cell_of(b.payload.enable()),
            differs: mask_a != mask_b,
        });
    }

    // Data: masked with the bits both sides consider meaningful.
    let joint = if ctx.opts.strict_be {
        Value::ones(width)
    } else {
        mask_a.mask_with(&mask_b)
    };
    let da = a.payload.data().resize(width).mask_with(&joint);
    let db = b.payload.data().resize(width).mask_with(&joint);
    let data_differs = if da == db {
        false
    } else if ctx.opts.x == XPolicy::Match {
        !da.differs_only_by_unknown(&db)
    } else {
        true
    };
    rows.push(FieldRow {
        name: ctx.data_label.clone(),
        a: Cell::Val(da),
        b: Cell::Val(db),
        differs: data_differs,
    });

    if ctx.spec.opc {
        let (oa, ob) = (payload_opc(a), payload_opc(b));
        rows.push(FieldRow {
            name: "r_opc".to_string(),
            a: opc_cell(oa),
            b: opc_cell(ob),
            differs: oa != ob,
        });
    }
    for (on, name) in [
        (ctx.spec.user, "user"),
        (ctx.spec.id, "id"),
        (ctx.spec.ecc, "ecc"),
    ] {
        if on {
            rows.push(row(name, side_channel(a, name), side_channel(b, name)));
        }
    }
    rows
}

fn cell_of(v: Option<&Value>) -> Cell {
    match v {
        Some(v) => Cell::Val(v.clone()),
        None => Cell::Missing,
    }
}

fn row(name: &str, a: Option<Value>, b: Option<Value>) -> FieldRow {
    let differs = match (&a, &b) {
        (Some(x), Some(y)) => x != y,
        (None, None) => false,
        _ => true,
    };
    FieldRow {
        name: name.to_string(),
        a: a.map(Cell::Val).unwrap_or(Cell::Missing),
        b: b.map(Cell::Val).unwrap_or(Cell::Missing),
        differs,
    }
}

fn wen_cell(wen: Option<bool>) -> Cell {
    match wen {
        Some(true) => Cell::Text("1 (LOAD)".to_string()),
        Some(false) => Cell::Text("0 (STORE)".to_string()),
        None => Cell::Missing,
    }
}

fn opc_cell(opc: Option<u8>) -> Cell {
    match opc {
        Some(v) => Cell::Text(v.to_string()),
        None => Cell::Missing,
    }
}

fn payload_add(beat: &Beat) -> Option<Value> {
    match &beat.payload {
        Payload::Req { add, .. } => Some(add.clone()),
        _ => None,
    }
}

fn payload_wen(beat: &Beat) -> Option<bool> {
    match &beat.payload {
        Payload::Req { wen, .. } => Some(*wen),
        _ => None,
    }
}

fn payload_opc(beat: &Beat) -> Option<u8> {
    match &beat.payload {
        Payload::Rsp { r_opc, .. } => Some(*r_opc),
        _ => None,
    }
}

fn side_channel(beat: &Beat, name: &str) -> Option<Value> {
    match (&beat.payload, name) {
        (Payload::Req { user, .. }, "user") => user.clone(),
        (Payload::Req { id, .. }, "id") => id.clone(),
        (Payload::Req { ecc, .. }, "ecc") => ecc.clone(),
        (Payload::Rsp { r_user, .. }, "user") => r_user.clone(),
        (Payload::Rsp { r_id, .. }, "id") => r_id.clone(),
        (Payload::Rsp { r_ecc, .. }, "ecc") => r_ecc.clone(),
        _ => None,
    }
}

/// Compact one-line rendering of a beat that has no counterpart.
pub fn describe(beat: &Beat) -> String {
    match &beat.payload {
        Payload::Req { add, wen, data, be, .. } => {
            let what = if *wen { "1 (LOAD)" } else { "0 (STORE)" };
            let payload = if *wen {
                "----".to_string()
            } else {
                format!("0x{}", data.to_hex_grouped(4))
            };
            format!(
                "add 0x{}   wen {what}   be 0x{}   data {payload}",
                add.to_hex_grouped(4),
                be.to_hex()
            )
        }
        Payload::Rsp { r_data, r_opc, .. } => {
            format!("r_data 0x{}   r_opc {r_opc}", r_data.to_hex_grouped(4))
        }
        Payload::Str { data, strb } => {
            format!("data 0x{}   strb 0x{}", data.to_hex_grouped(4), strb.to_hex())
        }
    }
}

/// `--x-policy=error`: refuse to go on if any *enabled* byte carries x/z.
pub fn check_unknowns(log: &LoadedLog, side: Side, ctx: &CmpCtx) -> Result<()> {
    if ctx.opts.x != XPolicy::Error {
        return Ok(());
    }
    let elem_bits = ctx.elem_bits(side);
    for beat in &log.beats {
        let mask = enable_mask(beat, elem_bits, ctx.data_width);
        let masked = beat.payload.data().resize(ctx.data_width).mask_with(&mask);
        if masked.unknown_count() > 0 {
            return Err(Error::UnknownBits {
                path: log.file.clone(),
                seq: beat.seq,
                field: match log.kind {
                    LogKind::HciResponse => "r_data".to_string(),
                    _ => "data".to_string(),
                },
            });
        }
    }
    Ok(())
}

/// Keep only the write requests (`wen == 0`) of an HCI request log; used when
/// comparing against a HWPE-Stream, which only carries written data.
pub fn keep_writes(log: &mut LoadedLog) -> usize {
    let before = log.beats.len();
    log.beats.retain(|b| matches!(&b.payload, Payload::Req { wen: false, .. }));
    before - log.beats.len()
}

/// Guard against being handed a log of the wrong kind by a caller.
pub fn expect_kind(log: &LoadedLog, kind: LogKind, path: &Path) -> Result<()> {
    if log.kind == kind {
        Ok(())
    } else {
        Err(Error::schema(path, format!("expected a {} log", kind.label())))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Iface, Note};
    use crate::repair::RepairInfo;
    use std::path::PathBuf;

    fn req_beat(seq: u64, cycle: u64, add: &str, data: &str, be: &str) -> Beat {
        Beat {
            seq,
            cycle,
            sub: None,
            payload: Payload::Req {
                add: Value::parse_hex(add, 32).unwrap(),
                wen: false,
                data: Value::parse_hex(data, 32).unwrap(),
                be: Value::parse_hex(be, 4).unwrap(),
                user: None,
                id: None,
                ecc: None,
            },
        }
    }

    fn req_log(beats: Vec<Beat>) -> LoadedLog {
        LoadedLog {
            file: PathBuf::from("a.json"),
            kind: LogKind::HciRequest,
            iface: Iface::Hci { dw: 32, aw: 32, bw: 8, uw: 0, iw: 0, ew: 0, ehw: 0 },
            hier_path: "tb.i_tracer".to_string(),
            beats,
            repair: RepairInfo::default(),
            notes: Vec::<Note>::new(),
        }
    }

    fn ctx(opts: CompareOptions) -> CmpCtx {
        let a = req_log(vec![]);
        let b = req_log(vec![]);
        CmpCtx::new(Mode::HciReq, &a, &b, 32, opts)
    }

    #[test]
    fn keys_never_mention_time() {
        for mode in [Mode::HciReq, Mode::HciRsp, Mode::ReqVsStream, Mode::RspVsStream, Mode::StreamVsStream] {
            let a = req_log(vec![]);
            let c = CmpCtx::new(mode, &a, &a, 32, CompareOptions::default());
            for name in c.key_names() {
                assert!(name != "cycle" && name != "seq", "{mode:?} leaked {name}");
            }
        }
        // ... and neither do the key fields themselves.
        let c = ctx(CompareOptions::default());
        let k = key_of(&req_beat(7, 1234, "0x0", "0x1", "0xf"), Side::A, &c);
        assert!(k.0.iter().all(|f| f.name != "cycle" && f.name != "seq"));
    }

    #[test]
    fn identical_content_at_different_times_has_the_same_key() {
        let c = ctx(CompareOptions::default());
        let early = req_beat(0, 10, "0x1c010000", "0xdeadbeef", "0xf");
        let late = req_beat(99, 99999, "0x1c010000", "0xdeadbeef", "0xf");
        assert_eq!(key_of(&early, Side::A, &c), key_of(&late, Side::B, &c));
        assert!(beats_equal(&early, &late, &c));
    }

    #[test]
    fn disabled_bytes_are_dont_care_unless_strict() {
        let a = req_beat(0, 1, "0x0", "0xdeadbeef", "0x3");
        let b = req_beat(0, 1, "0x0", "0x0000beef", "0x3");

        let relaxed = ctx(CompareOptions::default());
        assert!(beats_equal(&a, &b, &relaxed));
        assert_eq!(key_of(&a, Side::A, &relaxed), key_of(&b, Side::B, &relaxed));

        let strict = ctx(CompareOptions { strict_be: true, ..Default::default() });
        assert!(!beats_equal(&a, &b, &strict));
    }

    #[test]
    fn default_key_set_matches_the_documented_one() {
        let c = ctx(CompareOptions::default());
        assert_eq!(c.key_names(), vec!["add", "wen", "be", "data&be"]);
        let c = ctx(CompareOptions { ignore_add: true, ..Default::default() });
        assert_eq!(c.key_names(), vec!["wen", "be", "data&be"]);
        let c = ctx(CompareOptions { check_id: true, ..Default::default() });
        assert!(c.key_names().contains(&"id".to_string()));
    }

    #[test]
    fn x_policy_match_downgrades_a_difference() {
        let a = req_beat(0, 1, "0x0", "0xdeadbeef", "0xf");
        let b = req_beat(0, 1, "0x0", "0xdeadbeex", "0xf");
        assert!(!beats_equal(&a, &b, &ctx(CompareOptions::default())));
        let lenient = ctx(CompareOptions { x: XPolicy::Match, ..Default::default() });
        assert!(beats_equal(&a, &b, &lenient));
    }

    #[test]
    fn keep_writes_drops_loads() {
        let mut log = req_log(vec![
            req_beat(0, 1, "0x0", "0x1", "0xf"),
            Beat {
                seq: 1,
                cycle: 2,
                sub: None,
                payload: Payload::Req {
                    add: Value::parse_hex("0x4", 32).unwrap(),
                    wen: true,
                    data: Value::zeros(32),
                    be: Value::parse_hex("0xf", 4).unwrap(),
                    user: None,
                    id: None,
                    ecc: None,
                },
            },
        ]);
        assert_eq!(keep_writes(&mut log), 1);
        assert_eq!(log.beats.len(), 1);
    }
}
