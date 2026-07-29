// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Normalized, domain-agnostic representation of a transaction log.
//!
//! Note that `seq` and `cycle` live in [`Beat`], *outside* [`Payload`], and that
//! comparison keys are built from [`Payload`] alone: it is therefore
//! structurally impossible for the time of a transaction to influence a
//! comparison.

use std::path::PathBuf;

use crate::repair::RepairInfo;
use crate::value::Value;

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum LogKind {
    HciRequest,
    HciResponse,
    HwpeStream,
}

impl LogKind {
    pub fn label(self) -> &'static str {
        match self {
            LogKind::HciRequest => "HCI request",
            LogKind::HciResponse => "HCI response",
            LogKind::HwpeStream => "HWPE-Stream",
        }
    }
}

#[derive(Debug, Clone)]
pub enum Iface {
    Hci { dw: u32, aw: u32, bw: u32, uw: u32, iw: u32, ew: u32, ehw: u32 },
    Stream { data_width: u32, elem_width: u32, strb_width: u32 },
}

impl Iface {
    pub fn data_width(&self) -> u32 {
        match self {
            Iface::Hci { dw, .. } => *dw,
            Iface::Stream { data_width, .. } => *data_width,
        }
    }

    /// Number of data bits covered by one enable bit (`BW` or `ELEMENT_WIDTH`).
    pub fn elem_bits(&self) -> u32 {
        match self {
            Iface::Hci { bw, .. } => *bw,
            Iface::Stream { elem_width, .. } => *elem_width,
        }
    }

    /// One-line summary for the report header.
    pub fn summary(&self) -> String {
        match self {
            Iface::Hci { dw, aw, bw, uw, iw, ew, ehw } => {
                let mut s = format!("DW={dw} AW={aw} BW={bw}");
                for (name, w) in [("UW", uw), ("IW", iw), ("EW", ew), ("EHW", ehw)] {
                    if *w > 0 {
                        s.push_str(&format!(" {name}={w}"));
                    }
                }
                s
            }
            Iface::Stream { data_width, elem_width, strb_width } => {
                format!("DATA_WIDTH={data_width} ELEMENT_WIDTH={elem_width} STRB_WIDTH={strb_width}")
            }
        }
    }
}

#[derive(Debug, Clone)]
pub enum Payload {
    Req {
        add: Value,
        /// HCI polarity: `true` for a LOAD, `false` for a STORE. "Write enable
        /// asserted" therefore means `wen == false`.
        wen: bool,
        data: Value,
        be: Value,
        user: Option<Value>,
        id: Option<Value>,
        ecc: Option<Value>,
    },
    Rsp {
        r_data: Value,
        r_opc: u8,
        r_user: Option<Value>,
        r_id: Option<Value>,
        r_ecc: Option<Value>,
    },
    Str {
        data: Value,
        strb: Value,
    },
}

impl Payload {
    /// The data payload, whatever the domain.
    pub fn data(&self) -> &Value {
        match self {
            Payload::Req { data, .. } => data,
            Payload::Rsp { r_data, .. } => r_data,
            Payload::Str { data, .. } => data,
        }
    }

    /// The raw enable (`be` or `strb`), if the domain has one.
    pub fn enable(&self) -> Option<&Value> {
        match self {
            Payload::Req { be, .. } => Some(be),
            Payload::Rsp { .. } => None,
            Payload::Str { strb, .. } => Some(strb),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Beat {
    /// Index in the originating log; metadata only.
    pub seq: u64,
    /// Cycle of the handshake; metadata only, never compared.
    pub cycle: u64,
    /// Sub-beat index, set when this beat came out of `--split`.
    pub sub: Option<u32>,
    pub payload: Payload,
}

impl Beat {
    /// Waveform-friendly label, e.g. `#0042` or `#0042.1`.
    pub fn label(&self) -> String {
        match self.sub {
            Some(i) => format!("#{:04}.{}", self.seq, i),
            None => format!("#{:04}", self.seq),
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum NoteLevel {
    Info,
    Warn,
}

#[derive(Debug, Clone)]
pub struct Note {
    pub level: NoteLevel,
    pub text: String,
}

impl Note {
    pub fn info(text: impl Into<String>) -> Note {
        Note { level: NoteLevel::Info, text: text.into() }
    }

    pub fn warn(text: impl Into<String>) -> Note {
        Note { level: NoteLevel::Warn, text: text.into() }
    }
}

#[derive(Debug, Clone)]
pub struct LoadedLog {
    pub file: PathBuf,
    pub kind: LogKind,
    pub iface: Iface,
    /// Hierarchical path of the tracer instance, as recorded in the log.
    pub hier_path: String,
    pub beats: Vec<Beat>,
    pub repair: RepairInfo,
    pub notes: Vec<Note>,
}

impl LoadedLog {
    /// `path` field if the tracer recorded one, else the file name.
    pub fn display_name(&self) -> String {
        if self.hier_path.is_empty() {
            self.file.file_name().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default()
        } else {
            self.hier_path.clone()
        }
    }
}
