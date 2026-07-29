// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Recovery of transaction logs that were cut short.
//!
//! The tracers close the `transactions` array and the enclosing object from a
//! SystemVerilog `final` block. If the simulation is killed (`$fatal`, a
//! timeout, Ctrl-C) that block never runs and the log ends in the middle of the
//! array -- or of a transaction. Rather than losing the whole trace, the text is
//! cut back to the last complete transaction and the missing closing delimiters
//! are appended.
//!
//! Only cut points immediately after a `}`/`]` are considered safe, which
//! guarantees that a half-written transaction is dropped rather than turned into
//! an object with missing fields.

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct RepairInfo {
    pub repaired: bool,
    /// Bytes cut off the end of the file.
    pub discarded_bytes: usize,
    /// True when what was cut off was more than whitespace and a comma, i.e.
    /// when a partially written transaction was thrown away.
    pub dropped_partial_record: bool,
    /// Delimiters appended to close the document, e.g. `]}`.
    pub appended: String,
}

/// Attempt to turn a truncated log into a well-formed JSON document.
///
/// Returns `None` when no complete container was ever closed, i.e. when the file
/// was cut so early that nothing can be salvaged.
pub fn repair_truncated(text: &str) -> Option<(String, RepairInfo)> {
    let (offset, stack) = last_safe_point(text)?;

    let mut appended = String::with_capacity(stack.len());
    for open in stack.iter().rev() {
        appended.push(match open {
            b'{' => '}',
            _ => ']',
        });
    }

    let tail = &text[offset..];
    let info = RepairInfo {
        repaired: true,
        discarded_bytes: tail.len(),
        dropped_partial_record: tail.chars().any(|c| !c.is_whitespace() && c != ','),
        appended: appended.clone(),
    };

    let mut out = String::with_capacity(offset + appended.len());
    out.push_str(&text[..offset]);
    out.push_str(&appended);
    Some((out, info))
}

/// Byte offset just past the last closed container, plus the containers still
/// open at that point (outermost first).
fn last_safe_point(text: &str) -> Option<(usize, Vec<u8>)> {
    enum St {
        Normal,
        Str,
        StrEsc,
    }

    let bytes = text.as_bytes();
    let mut st = St::Normal;
    let mut stack: Vec<u8> = Vec::new();
    let mut best: Option<(usize, usize)> = None;

    for (i, b) in bytes.iter().enumerate() {
        match st {
            St::Str => {
                st = match b {
                    b'\\' => St::StrEsc,
                    b'"' => St::Normal,
                    _ => St::Str,
                }
            }
            St::StrEsc => st = St::Str,
            St::Normal => match b {
                b'"' => st = St::Str,
                b'{' | b'[' => stack.push(*b),
                b'}' | b']' => {
                    stack.pop();
                    // The prefix up to here is a valid partial document that can
                    // be completed by closing whatever is still open.
                    best = Some((i + 1, stack.len()));
                }
                _ => {}
            },
        }
    }

    let (offset, depth) = best?;
    // The container stack is prefix-stable: entries below `depth` at the safe
    // point can never have been popped afterwards, so the current stack's first
    // `depth` entries are exactly the ones that were open there.
    Some((offset, stack[..depth.min(stack.len())].to_vec()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEADER: &str = concat!(
        "{\n  \"schema\": \"hci_transaction_request-v1\",\n",
        "  \"interface\": { \"DW\": 32, \"AW\": 32, \"BW\": 8 },\n",
        "  \"path\": \"tb.i_tracer\",\n  \"transactions\": ["
    );
    const TX0: &str = "\n    {\"seq\": 0, \"cycle\": 1, \"add\": \"0x0\", \"wen\": 0, \"data\": \"0x1\", \"be\": \"0xf\"}";
    const TX1: &str = "\n    {\"seq\": 1, \"cycle\": 3, \"add\": \"0x4\", \"wen\": 0, \"data\": \"0x2\", \"be\": \"0xf\"}";

    fn repair(text: &str) -> (String, RepairInfo) {
        repair_truncated(text).expect("should be repairable")
    }

    #[test]
    fn cut_in_the_middle_of_a_transaction_drops_it() {
        let text = format!("{HEADER}{TX0},{TX1}\n    {{\"seq\": 2, \"cycl");
        let (fixed, info) = repair(&text);
        assert_eq!(info.appended, "]}");
        assert!(info.dropped_partial_record);
        assert!(fixed.ends_with("\"be\": \"0xf\"}]}"));
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert_eq!(v["transactions"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn cut_right_after_a_comma_leaves_no_dangling_comma() {
        let text = format!("{HEADER}{TX0},");
        let (fixed, info) = repair(&text);
        assert!(!info.dropped_partial_record);
        assert_eq!(info.discarded_bytes, 1);
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert_eq!(v["transactions"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn cut_right_after_a_transaction_needs_only_the_closers() {
        let text = format!("{HEADER}{TX0}");
        let (fixed, info) = repair(&text);
        assert_eq!(info.discarded_bytes, 0);
        assert!(!info.dropped_partial_record);
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert_eq!(v["transactions"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn cut_before_the_first_transaction_yields_an_empty_log() {
        let text = format!("{HEADER}\n    {{\"seq\": 0, \"cycle\"");
        let (fixed, info) = repair(&text);
        assert_eq!(info.appended, "}");
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert!(v["transactions"].is_null());
        assert_eq!(v["interface"]["DW"], 32);
    }

    #[test]
    fn cut_inside_a_string_containing_json_delimiters() {
        let text = format!(
            "{}{}\n    {{\"seq\": 1, \"note\": \"}}]}} \\\" oops",
            HEADER.replace("tb.i_tracer", "tb.gen[0].i_tracer"),
            TX0
        );
        let (fixed, info) = repair(&text);
        assert!(info.dropped_partial_record);
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert_eq!(v["transactions"].as_array().unwrap().len(), 1);
        assert_eq!(v["path"], "tb.gen[0].i_tracer");
    }

    #[test]
    fn cut_after_a_lone_backslash_inside_a_string() {
        let text = format!("{HEADER}{TX0}\n    {{\"seq\": 1, \"note\": \"abc\\");
        let (fixed, _) = repair(&text);
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert_eq!(v["transactions"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn cut_inside_a_number() {
        let text = format!("{HEADER}{TX0},{TX1}\n    {{\"seq\": 2, \"cycle\": 12");
        let (fixed, _) = repair(&text);
        let v: serde_json::Value = serde_json::from_str(&fixed).unwrap();
        assert_eq!(v["transactions"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn cut_before_the_interface_closes_is_unrecoverable() {
        assert!(repair_truncated("{\n  \"schema\": \"hci_transaction_re").is_none());
        assert!(repair_truncated("{\n  \"interface\": { \"DW\": 3").is_none());
        assert!(repair_truncated("").is_none());
        assert!(repair_truncated("   \n  ").is_none());
    }

    #[test]
    fn a_complete_document_is_cut_back_to_itself() {
        let text = format!("{HEADER}{TX0}\n  ]\n}}\n");
        let (fixed, info) = repair(&text);
        assert_eq!(info.appended, "");
        assert_eq!(serde_json::from_str::<serde_json::Value>(&fixed).unwrap()["transactions"]
            .as_array()
            .unwrap()
            .len(), 1);
    }
}
