// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! `serde` mirrors of the three JSON schemas in `tracer/` (HCI) and
//! `hwpe-stream/tracer/` (HWPE-Stream).
//!
//! Fields stay as strings here: their widths are only known once
//! `interface` has been read, so hexadecimal parsing happens in [`crate::load`].

use serde::Deserialize;

pub const TAG_HCI_REQUEST: &str = "hci_transaction_request-v1";
pub const TAG_HCI_RESPONSE: &str = "hci_transaction_response-v1";
pub const TAG_HWPE_STREAM: &str = "hwpe_stream_transaction-v1";

/// Just enough of any log to tell which schema it follows.
#[derive(Debug, Deserialize)]
pub struct SchemaProbe {
    #[serde(default)]
    pub schema: String,
}

#[derive(Debug, Deserialize)]
pub struct HciIfaceRaw {
    #[serde(rename = "DW")]
    pub dw: u32,
    #[serde(rename = "AW")]
    pub aw: u32,
    #[serde(rename = "BW")]
    pub bw: u32,
    #[serde(rename = "UW", default)]
    pub uw: u32,
    #[serde(rename = "IW", default)]
    pub iw: u32,
    #[serde(rename = "EW", default)]
    pub ew: u32,
    #[serde(rename = "EHW", default)]
    pub ehw: u32,
}

#[derive(Debug, Deserialize)]
pub struct StreamIfaceRaw {
    #[serde(rename = "DATA_WIDTH")]
    pub data_width: u32,
    #[serde(rename = "ELEMENT_WIDTH", default = "default_element_width")]
    pub element_width: u32,
    #[serde(rename = "STRB_WIDTH", default)]
    pub strb_width: Option<u32>,
}

fn default_element_width() -> u32 {
    8
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HciRequestLog {
    pub schema: String,
    pub interface: HciIfaceRaw,
    #[serde(default)]
    pub path: String,
    /// Defaulted so that a file truncated before the array even opened still
    /// loads (as an empty log) rather than failing.
    #[serde(default)]
    pub transactions: Vec<HciRequestRaw>,
}

#[derive(Debug, Deserialize)]
pub struct HciRequestRaw {
    #[serde(default)]
    pub seq: u64,
    #[serde(default)]
    pub cycle: u64,
    pub add: String,
    pub wen: u8,
    pub data: String,
    pub be: String,
    #[serde(default)]
    pub user: Option<String>,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub ecc: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HciResponseLog {
    pub schema: String,
    pub interface: HciIfaceRaw,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub transactions: Vec<HciResponseRaw>,
}

#[derive(Debug, Deserialize)]
pub struct HciResponseRaw {
    #[serde(default)]
    pub seq: u64,
    #[serde(default)]
    pub cycle: u64,
    pub r_data: String,
    pub r_opc: u8,
    #[serde(default)]
    pub r_user: Option<String>,
    #[serde(default)]
    pub r_id: Option<String>,
    #[serde(default)]
    pub r_ecc: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HwpeStreamLog {
    pub schema: String,
    pub interface: StreamIfaceRaw,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub transactions: Vec<StreamBeatRaw>,
}

#[derive(Debug, Deserialize)]
pub struct StreamBeatRaw {
    #[serde(default)]
    pub seq: u64,
    #[serde(default)]
    pub cycle: u64,
    pub data: String,
    pub strb: String,
}
