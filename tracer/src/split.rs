// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Width normalization between two logs.
//!
//! Comparing a `DW = 64` HCI port against a 32-bit HWPE-Stream is a routine
//! thing to want, but reinterpreting one wide beat as two narrow ones is also a
//! good way to paper over a genuine packing bug. So it never happens implicitly:
//! mismatched widths are an error unless `--split` says otherwise.

use std::str::FromStr;

use crate::error::{Error, Result};
use crate::model::{Beat, Iface, LoadedLog, Note, Payload};

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum SplitMode {
    /// Infer the ratio from the two declared widths.
    Auto,
    /// Require exactly this ratio, as a guard against typos.
    Ratio(u32),
}

impl FromStr for SplitMode {
    type Err = String;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        if s.eq_ignore_ascii_case("auto") {
            return Ok(SplitMode::Auto);
        }
        match s.parse::<u32>() {
            Ok(n) if n >= 1 => Ok(SplitMode::Ratio(n)),
            _ => Err(format!("expected `auto` or a positive integer, found `{s}`")),
        }
    }
}

/// Bring both logs to a common data width, returning it.
pub fn normalize_widths(
    a: &mut LoadedLog,
    b: &mut LoadedLog,
    split: Option<SplitMode>,
    drop_empty: bool,
) -> Result<u32> {
    let (wa, wb) = (a.iface.data_width(), b.iface.data_width());
    if wa == wb {
        if drop_empty {
            drop_empty_beats(a);
            drop_empty_beats(b);
        }
        return Ok(wa);
    }

    let Some(mode) = split else {
        return Err(Error::Width(format!(
            "data width mismatch: A ({}, {}) vs B ({}, {})\n  \
             hint: pass --split to compare each wide beat as several narrow ones \
             (little-endian element order: sub-beat 0 carries the low bits)",
            a.kind.label(),
            a.iface.summary(),
            b.kind.label(),
            b.iface.summary()
        )));
    };

    let (wide, narrow) = if wa > wb { (wa, wb) } else { (wb, wa) };
    if wide % narrow != 0 {
        return Err(Error::Width(format!(
            "cannot split {wide} bits into beats of {narrow} bits: \
             the narrower width does not divide the wider one"
        )));
    }
    let ratio = wide / narrow;
    if let SplitMode::Ratio(n) = mode {
        if n != ratio {
            return Err(Error::Width(format!(
                "--split={n} was requested but the declared widths ({wide} and {narrow}) \
                 imply a ratio of {ratio}"
            )));
        }
    }

    let target = if wa > wb { &mut *a } else { &mut *b };
    let elem_bits = target.iface.elem_bits();
    if narrow % elem_bits != 0 {
        return Err(Error::Width(format!(
            "cannot split into {narrow}-bit beats: the enable granularity of \
             {elem_bits} bits does not divide it"
        )));
    }
    split_log(target, ratio, narrow, elem_bits);
    target.notes.push(Note::info(format!(
        "split each {wide}-bit beat into {ratio} beats of {narrow} bits \
         (sub-beat 0 = low bits)"
    )));

    if drop_empty {
        drop_empty_beats(a);
        drop_empty_beats(b);
    }
    Ok(narrow)
}

fn split_log(log: &mut LoadedLog, ratio: u32, narrow: u32, elem_bits: u32) {
    let mut out = Vec::with_capacity(log.beats.len() * ratio as usize);
    for beat in &log.beats {
        for i in 0..ratio {
            out.push(split_beat(beat, i, narrow, elem_bits));
        }
    }
    log.beats = out;
    log.iface = match &log.iface {
        Iface::Hci { aw, bw, uw, iw, ew, ehw, .. } => Iface::Hci {
            dw: narrow,
            aw: *aw,
            bw: *bw,
            uw: *uw,
            iw: *iw,
            ew: *ew,
            ehw: *ehw,
        },
        Iface::Stream { elem_width, .. } => Iface::Stream {
            data_width: narrow,
            elem_width: *elem_width,
            strb_width: narrow / elem_width,
        },
    };
}

fn split_beat(beat: &Beat, i: u32, narrow: u32, elem_bits: u32) -> Beat {
    let lo = i * narrow;
    let en_lo = i * (narrow / elem_bits);
    let en_len = narrow / elem_bits;
    let payload = match &beat.payload {
        Payload::Req { add, wen, data, be, user, id, ecc } => Payload::Req {
            add: add.add_u64((i as u64) * (narrow as u64) / 8),
            wen: *wen,
            data: data.slice(lo, narrow),
            be: be.slice(en_lo, en_len),
            user: user.clone(),
            id: id.clone(),
            ecc: ecc.clone(),
        },
        Payload::Rsp { r_data, r_opc, r_user, r_id, r_ecc } => Payload::Rsp {
            r_data: r_data.slice(lo, narrow),
            r_opc: *r_opc,
            r_user: r_user.clone(),
            r_id: r_id.clone(),
            r_ecc: r_ecc.clone(),
        },
        Payload::Str { data, strb } => Payload::Str {
            data: data.slice(lo, narrow),
            strb: strb.slice(en_lo, en_len),
        },
    };
    Beat { seq: beat.seq, cycle: beat.cycle, sub: Some(i), payload }
}

fn drop_empty_beats(log: &mut LoadedLog) {
    log.beats.retain(|b| match b.payload.enable() {
        Some(en) => !en.is_zero(),
        None => true,
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::LogKind;
    use crate::repair::RepairInfo;
    use crate::value::Value;
    use std::path::PathBuf;

    fn hci_log(dw: u32, bw: u32, beats: Vec<Beat>) -> LoadedLog {
        LoadedLog {
            file: PathBuf::from("a.json"),
            kind: LogKind::HciRequest,
            iface: Iface::Hci { dw, aw: 32, bw, uw: 0, iw: 0, ew: 0, ehw: 0 },
            hier_path: String::new(),
            beats,
            repair: RepairInfo::default(),
            notes: Vec::new(),
        }
    }

    fn stream_log(dw: u32, ew: u32, beats: Vec<Beat>) -> LoadedLog {
        LoadedLog {
            file: PathBuf::from("b.json"),
            kind: LogKind::HwpeStream,
            iface: Iface::Stream { data_width: dw, elem_width: ew, strb_width: dw / ew },
            hier_path: String::new(),
            beats,
            repair: RepairInfo::default(),
            notes: Vec::new(),
        }
    }

    fn req(add: &str, data: &str, be: &str, dw: u32, sw: u32) -> Beat {
        Beat {
            seq: 0,
            cycle: 0,
            sub: None,
            payload: Payload::Req {
                add: Value::parse_hex(add, 32).unwrap(),
                wen: false,
                data: Value::parse_hex(data, dw).unwrap(),
                be: Value::parse_hex(be, sw).unwrap(),
                user: None,
                id: None,
                ecc: None,
            },
        }
    }

    #[test]
    fn equal_widths_need_no_split() {
        let mut a = hci_log(32, 8, vec![]);
        let mut b = stream_log(32, 8, vec![]);
        assert_eq!(normalize_widths(&mut a, &mut b, None, false).unwrap(), 32);
    }

    #[test]
    fn mismatched_widths_are_refused_and_the_message_points_at_split() {
        let mut a = hci_log(64, 8, vec![]);
        let mut b = stream_log(32, 8, vec![]);
        let err = normalize_widths(&mut a, &mut b, None, false).unwrap_err();
        assert!(err.to_string().contains("--split"), "{err}");
    }

    #[test]
    fn split_is_little_endian_and_carries_be_and_add_along() {
        let mut a = hci_log(64, 8, vec![req("0x1c010000", "0x0123456789abcdef", "0xf3", 64, 8)]);
        let mut b = stream_log(32, 8, vec![]);
        assert_eq!(normalize_widths(&mut a, &mut b, Some(SplitMode::Auto), false).unwrap(), 32);
        assert_eq!(a.beats.len(), 2);
        assert_eq!(a.iface.data_width(), 32);

        let Payload::Req { add, data, be, .. } = &a.beats[0].payload else { panic!() };
        assert_eq!(data.to_hex(), "89abcdef");
        assert_eq!(be.to_hex(), "3");
        assert_eq!(add.to_hex(), "1c010000");
        assert_eq!(a.beats[0].sub, Some(0));

        let Payload::Req { add, data, be, .. } = &a.beats[1].payload else { panic!() };
        assert_eq!(data.to_hex(), "01234567");
        assert_eq!(be.to_hex(), "f");
        assert_eq!(add.to_hex(), "1c010004");
        assert_eq!(a.beats[1].label(), "#0000.1");
    }

    #[test]
    fn split_512_into_16_narrow_beats() {
        let hex: String = (0..128).map(|i| char::from_digit(i % 16, 16).unwrap()).collect();
        let mut a = hci_log(512, 8, vec![req("0x0", &hex, "0xffffffffffffffff", 512, 64)]);
        let mut b = stream_log(32, 8, vec![]);
        assert_eq!(normalize_widths(&mut a, &mut b, Some(SplitMode::Auto), false).unwrap(), 32);
        assert_eq!(a.beats.len(), 16);
    }

    #[test]
    fn a_wrong_explicit_ratio_is_refused() {
        let mut a = hci_log(64, 8, vec![]);
        let mut b = stream_log(32, 8, vec![]);
        let err = normalize_widths(&mut a, &mut b, Some(SplitMode::Ratio(4)), false).unwrap_err();
        assert!(err.to_string().contains("ratio of 2"), "{err}");
    }

    #[test]
    fn non_divisible_widths_are_refused_even_with_split() {
        let mut a = hci_log(48, 8, vec![]);
        let mut b = stream_log(32, 8, vec![]);
        assert!(normalize_widths(&mut a, &mut b, Some(SplitMode::Auto), false).is_err());
    }

    #[test]
    fn drop_empty_removes_fully_disabled_beats() {
        let mut a = hci_log(
            32,
            8,
            vec![req("0x0", "0x1", "0xf", 32, 4), req("0x4", "0x0", "0x0", 32, 4)],
        );
        let mut b = stream_log(32, 8, vec![]);
        normalize_widths(&mut a, &mut b, None, true).unwrap();
        assert_eq!(a.beats.len(), 1);
    }

    #[test]
    fn split_mode_parsing() {
        assert_eq!("auto".parse::<SplitMode>(), Ok(SplitMode::Auto));
        assert_eq!("AUTO".parse::<SplitMode>(), Ok(SplitMode::Auto));
        assert_eq!("4".parse::<SplitMode>(), Ok(SplitMode::Ratio(4)));
        assert!("0".parse::<SplitMode>().is_err());
        assert!("nope".parse::<SplitMode>().is_err());
    }
}
