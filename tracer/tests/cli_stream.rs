// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! `stream-vs-stream`, and the `show` subcommand.

mod common;

use common::{fixture, run};

#[test]
fn identical_streams_match() {
    run(&[
        "stream-vs-stream",
        "--a",
        &fixture("stream/str_a_basic.json"),
        "--b",
        &fixture("stream/str_b_basic.json"),
    ])
    .assert_code(0)
    .assert_out("keys      : strb, data&strb")
    .assert_out("8/8 transactions match");
}

#[test]
fn a_strobe_difference_is_reported_and_can_be_ignored() {
    let base = [
        "stream-vs-stream",
        "--a",
        &fixture("stream/str_a_basic.json"),
        "--b",
        &fixture("stream/str_b_strb_mismatch.json"),
    ]
    .map(String::from);
    let refs: Vec<&str> = base.iter().map(|s| s.as_str()).collect();

    let out = run(&refs);
    out.assert_code(1).assert_out("strb");
    assert_eq!(out.summary("mismatched"), 1);

    let mut ignore = refs.clone();
    ignore.push("--ignore-en");
    // The data that both sides agree is meaningful is identical.
    run(&ignore).assert_code(0).assert_out("MATCH");
}

#[test]
fn a_shorter_stream_shows_up_as_a_missing_beat() {
    let out = run(&[
        "stream-vs-stream",
        "--a",
        &fixture("stream/str_a_basic.json"),
        "--b",
        &fixture("stream/str_b_shorter.json"),
    ]);
    out.assert_code(1).assert_out("only in A");
    assert_eq!(out.summary("only in A"), 1);
    assert_eq!(out.summary("mismatched"), 0);
}

#[test]
fn show_prints_every_transaction_of_a_log() {
    let out = run(&["show", &fixture("hci/req_a_dw64.json")]);
    out.assert_code(0)
        .assert_out("HCI request log")
        .assert_out("DW=64")
        .assert_out("count     : 4")
        .assert_out("#0003");

    run(&["show", &fixture("stream/str_ew4.json")])
        .assert_code(0)
        .assert_out("HWPE-Stream log")
        .assert_out("strb 0xff");
}
