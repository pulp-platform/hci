// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Reading a log file: repair, parse, validate, normalize.

use std::path::Path;

use serde::de::DeserializeOwned;

use crate::error::{Error, Result};
use crate::model::{Beat, Iface, LoadedLog, LogKind, Note, Payload};
use crate::repair::{repair_truncated, RepairInfo};
use crate::schema::*;
use crate::value::Value;

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum RepairMode {
    /// Repair a log that was cut short by an aborted simulation.
    Auto,
    /// Report the parse error as it stands.
    Never,
}

fn read_text(path: &Path) -> Result<String> {
    std::fs::read_to_string(path).map_err(|e| Error::io(path, e))
}

fn parse_with_repair<T: DeserializeOwned>(
    path: &Path,
    text: &str,
    mode: RepairMode,
) -> Result<(T, RepairInfo)> {
    match serde_json::from_str::<T>(text) {
        Ok(v) => Ok((v, RepairInfo::default())),
        Err(e) => {
            let truncated = e.classify() == serde_json::error::Category::Eof;
            if mode == RepairMode::Never || !truncated {
                return Err(Error::Json { path: path.to_path_buf(), source: e });
            }
            let Some((fixed, info)) = repair_truncated(text) else {
                return Err(Error::Truncated {
                    path: path.to_path_buf(),
                    detail: format!("not even the header was written completely ({e})"),
                });
            };
            match serde_json::from_str::<T>(&fixed) {
                Ok(v) => Ok((v, info)),
                Err(e2) => Err(Error::Truncated {
                    path: path.to_path_buf(),
                    detail: format!("the header itself is incomplete ({e2})"),
                }),
            }
        }
    }
}

/// Check the schema tag *before* the full parse, so that handing the tool a
/// response log where a request log belongs produces "this is a response log"
/// rather than "missing field `add`".
fn check_tag_first(path: &Path, text: &str, expected: &str) -> Result<()> {
    let probe: SchemaProbe = match serde_json::from_str(text) {
        Ok(p) => p,
        // Not parseable yet: let the real parse (and the repair pass) report it.
        Err(_) => match repair_truncated(text).and_then(|(f, _)| serde_json::from_str(&f).ok()) {
            Some(p) => p,
            None => return Ok(()),
        },
    };
    check_tag(path, &probe.schema, expected)
}

fn check_tag(path: &Path, found: &str, expected: &str) -> Result<()> {
    if found == expected {
        return Ok(());
    }
    let hint = match found {
        TAG_HCI_REQUEST => " (this is an HCI *request* log)",
        TAG_HCI_RESPONSE => " (this is an HCI *response* log)",
        TAG_HWPE_STREAM => " (this is a HWPE-Stream log)",
        _ => "",
    };
    Err(Error::schema(
        path,
        format!("expected a log with schema `{expected}`, found `{found}`{hint}"),
    ))
}

fn field(path: &Path, seq: u64, name: &str, text: &str, width: u32) -> Result<Value> {
    Value::parse_hex(text, width).map_err(|e| Error::Field {
        path: path.to_path_buf(),
        seq: Some(seq),
        field: name.to_string(),
        msg: e.to_string(),
    })
}

fn opt_field(
    path: &Path,
    seq: u64,
    name: &str,
    text: &Option<String>,
    width: u32,
) -> Result<Option<Value>> {
    match (width, text) {
        (0, _) | (_, None) => Ok(None),
        (w, Some(t)) => Ok(Some(field(path, seq, name, t, w)?)),
    }
}

fn hci_iface(path: &Path, raw: &HciIfaceRaw) -> Result<Iface> {
    if raw.bw == 0 || raw.dw % raw.bw != 0 {
        return Err(Error::schema(
            path,
            format!("interface declares DW={} and BW={}, but BW must divide DW", raw.dw, raw.bw),
        ));
    }
    Ok(Iface::Hci {
        dw: raw.dw,
        aw: raw.aw,
        bw: raw.bw,
        uw: raw.uw,
        iw: raw.iw,
        ew: raw.ew,
        ehw: raw.ehw,
    })
}

fn note_unknowns(notes: &mut Vec<Note>, count: usize, what: &str) {
    if count > 0 {
        notes.push(Note::info(format!(
            "{count} transaction(s) carry x/z bits in {what}"
        )));
    }
}

fn note_repair(notes: &mut Vec<Note>, path: &Path, info: &RepairInfo) {
    if !info.repaired {
        return;
    }
    let partial = if info.dropped_partial_record {
        ", dropping one partially written transaction"
    } else {
        ""
    };
    notes.push(Note::warn(format!(
        "{} was cut short and has been auto-repaired: discarded {} trailing byte(s){partial}. \
         The simulation probably ended before the tracer's final block ran.",
        path.display(),
        info.discarded_bytes
    )));
}

pub fn load_hci_request(path: &Path, mode: RepairMode) -> Result<LoadedLog> {
    let text = read_text(path)?;
    check_tag_first(path, &text, TAG_HCI_REQUEST)?;
    let (log, repair): (HciRequestLog, _) = parse_with_repair(path, &text, mode)?;
    check_tag(path, &log.schema, TAG_HCI_REQUEST)?;
    let iface = hci_iface(path, &log.interface)?;
    let (dw, aw, bw) = (log.interface.dw, log.interface.aw, log.interface.bw);
    let strb_bits = dw / bw;

    let mut notes = Vec::new();
    note_repair(&mut notes, path, &repair);

    let mut beats = Vec::with_capacity(log.transactions.len());
    let mut unknowns = 0usize;
    for tx in &log.transactions {
        let data = field(path, tx.seq, "data", &tx.data, dw)?;
        let be = field(path, tx.seq, "be", &tx.be, strb_bits)?;
        if data.unknown_count() > 0 || be.unknown_count() > 0 {
            unknowns += 1;
        }
        beats.push(Beat {
            seq: tx.seq,
            cycle: tx.cycle,
            sub: None,
            payload: Payload::Req {
                add: field(path, tx.seq, "add", &tx.add, aw)?,
                wen: tx.wen != 0,
                data,
                be,
                user: opt_field(path, tx.seq, "user", &tx.user, log.interface.uw)?,
                id: opt_field(path, tx.seq, "id", &tx.id, log.interface.iw)?,
                ecc: opt_field(path, tx.seq, "ecc", &tx.ecc, log.interface.ew)?,
            },
        });
    }
    note_unknowns(&mut notes, unknowns, "`data` or `be`");

    Ok(LoadedLog {
        file: path.to_path_buf(),
        kind: LogKind::HciRequest,
        iface,
        hier_path: log.path,
        beats,
        repair,
        notes,
    })
}

pub fn load_hci_response(path: &Path, mode: RepairMode) -> Result<LoadedLog> {
    let text = read_text(path)?;
    check_tag_first(path, &text, TAG_HCI_RESPONSE)?;
    let (log, repair): (HciResponseLog, _) = parse_with_repair(path, &text, mode)?;
    check_tag(path, &log.schema, TAG_HCI_RESPONSE)?;
    let iface = hci_iface(path, &log.interface)?;
    let dw = log.interface.dw;

    let mut notes = Vec::new();
    note_repair(&mut notes, path, &repair);

    let mut beats = Vec::with_capacity(log.transactions.len());
    let mut unknowns = 0usize;
    for tx in &log.transactions {
        let r_data = field(path, tx.seq, "r_data", &tx.r_data, dw)?;
        if r_data.unknown_count() > 0 {
            unknowns += 1;
        }
        beats.push(Beat {
            seq: tx.seq,
            cycle: tx.cycle,
            sub: None,
            payload: Payload::Rsp {
                r_data,
                r_opc: tx.r_opc,
                r_user: opt_field(path, tx.seq, "r_user", &tx.r_user, log.interface.uw)?,
                r_id: opt_field(path, tx.seq, "r_id", &tx.r_id, log.interface.iw)?,
                r_ecc: opt_field(path, tx.seq, "r_ecc", &tx.r_ecc, log.interface.ew)?,
            },
        });
    }
    note_unknowns(&mut notes, unknowns, "`r_data`");

    Ok(LoadedLog {
        file: path.to_path_buf(),
        kind: LogKind::HciResponse,
        iface,
        hier_path: log.path,
        beats,
        repair,
        notes,
    })
}

pub fn load_hwpe_stream(path: &Path, mode: RepairMode) -> Result<LoadedLog> {
    let text = read_text(path)?;
    check_tag_first(path, &text, TAG_HWPE_STREAM)?;
    let (log, repair): (HwpeStreamLog, _) = parse_with_repair(path, &text, mode)?;
    check_tag(path, &log.schema, TAG_HWPE_STREAM)?;

    let dw = log.interface.data_width;
    let ew = log.interface.element_width;
    if ew == 0 || dw % ew != 0 {
        return Err(Error::schema(
            path,
            format!(
                "interface declares DATA_WIDTH={dw} and ELEMENT_WIDTH={ew}, \
                 but ELEMENT_WIDTH must divide DATA_WIDTH"
            ),
        ));
    }
    let strb_bits = dw / ew;
    if let Some(declared) = log.interface.strb_width {
        if declared != strb_bits {
            return Err(Error::schema(
                path,
                format!(
                    "interface declares STRB_WIDTH={declared} but DATA_WIDTH/ELEMENT_WIDTH \
                     is {strb_bits}"
                ),
            ));
        }
    }

    let mut notes = Vec::new();
    note_repair(&mut notes, path, &repair);

    let mut beats = Vec::with_capacity(log.transactions.len());
    let mut unknowns = 0usize;
    let mut partial_strb = 0usize;
    for tx in &log.transactions {
        let data = field(path, tx.seq, "data", &tx.data, dw)?;
        let strb = field(path, tx.seq, "strb", &tx.strb, strb_bits)?;
        if data.unknown_count() > 0 || strb.unknown_count() > 0 {
            unknowns += 1;
        }
        if strb != Value::ones(strb_bits) {
            partial_strb += 1;
        }
        beats.push(Beat {
            seq: tx.seq,
            cycle: tx.cycle,
            sub: None,
            payload: Payload::Str { data, strb },
        });
    }
    note_unknowns(&mut notes, unknowns, "`data` or `strb`");
    if partial_strb > 0 {
        notes.push(Note::info(format!(
            "{partial_strb} beat(s) have a partial `strb`; the masked-off data bits are \
             treated as don't-care"
        )));
    }

    Ok(LoadedLog {
        file: path.to_path_buf(),
        kind: LogKind::HwpeStream,
        iface: Iface::Stream { data_width: dw, elem_width: ew, strb_width: strb_bits },
        hier_path: log.path,
        beats,
        repair,
        notes,
    })
}

/// Detect which schema a file follows, for the `show` subcommand.
pub fn probe_kind(path: &Path) -> Result<LogKind> {
    let text = read_text(path)?;
    let probe: SchemaProbe = match serde_json::from_str(&text) {
        Ok(p) => p,
        Err(e) if e.classify() == serde_json::error::Category::Eof => {
            let Some((fixed, _)) = repair_truncated(&text) else {
                return Err(Error::Truncated {
                    path: path.to_path_buf(),
                    detail: format!("{e}"),
                });
            };
            serde_json::from_str(&fixed)
                .map_err(|e| Error::Json { path: path.to_path_buf(), source: e })?
        }
        Err(e) => return Err(Error::Json { path: path.to_path_buf(), source: e }),
    };
    match probe.schema.as_str() {
        TAG_HCI_REQUEST => Ok(LogKind::HciRequest),
        TAG_HCI_RESPONSE => Ok(LogKind::HciResponse),
        TAG_HWPE_STREAM => Ok(LogKind::HwpeStream),
        other => Err(Error::schema(
            path,
            format!("unrecognized schema tag `{other}`"),
        )),
    }
}
