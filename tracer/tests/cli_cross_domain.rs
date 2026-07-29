// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Comparing an HCI log against a HWPE-Stream log, in both directions.

mod common;

use common::{fixture, run};

#[test]
fn write_requests_match_the_stream_that_carries_them() {
    run(&[
        "hci-req-vs-stream",
        "--hci",
        &fixture("hci/req_a_basic.json"),
        "--stream",
        &fixture("stream/str_a_basic.json"),
    ])
    .assert_code(0)
    .assert_out("keys      : en, data&en")
    .assert_out("MATCH");
}

#[test]
fn read_requests_are_left_out_and_said_so() {
    // A HWPE-Stream carries no read requests, so `wen == 1` entries are filtered.
    run(&[
        "hci-req-vs-stream",
        "--hci",
        &fixture("hci/req_a_with_loads.json"),
        "--stream",
        &fixture("stream/str_a_basic.json"),
    ])
    .assert_code(0)
    .assert_out("2 load request(s) (wen=1) were left out")
    .assert_out("MATCH");
}

#[test]
fn be_and_strb_are_compared_as_enabled_bits_not_as_encodings() {
    // be = 0xf with BW = 8 enables the same 32 bits as strb = 0xff with
    // ELEMENT_WIDTH = 4.
    run(&[
        "hci-req-vs-stream",
        "--hci",
        &fixture("hci/req_a_basic.json"),
        "--stream",
        &fixture("stream/str_ew4.json"),
    ])
    .assert_code(0)
    .assert_out("ELEMENT_WIDTH=4")
    .assert_out("MATCH");
}

#[test]
fn differing_widths_are_refused_until_split_is_asked_for() {
    let base = [
        "hci-req-vs-stream",
        "--hci",
        &fixture("hci/req_a_dw64.json"),
        "--stream",
        &fixture("stream/str_from_dw64.json"),
    ]
    .map(String::from);
    let refs: Vec<&str> = base.iter().map(|s| s.as_str()).collect();

    run(&refs)
        .assert_code(2)
        .assert_err("data width mismatch")
        .assert_err("--split");

    let mut ok = refs.clone();
    ok.push("--split");
    run(&ok).assert_code(0).assert_out("split each 64-bit beat into 2 beats of 32 bits");

    let mut wrong = refs.clone();
    wrong.push("--split=4");
    run(&wrong).assert_code(2).assert_err("imply a ratio of 2");
}

#[test]
fn responses_match_the_stream_they_feed() {
    run(&[
        "hci-rsp-vs-stream",
        "--hci",
        &fixture("hci/rsp_a_basic.json"),
        "--stream",
        &fixture("stream/str_a_basic.json"),
    ])
    .assert_code(0)
    .assert_out("MATCH");
}

#[test]
fn a_partial_strb_makes_the_masked_bytes_dont_care_for_a_response() {
    // A response has no byte enables of its own, so the stream's `strb` decides
    // which bits are meaningful. This is the pair-aware verdict at work.
    run(&[
        "hci-rsp-vs-stream",
        "--hci",
        &fixture("hci/rsp_a_basic.json"),
        "--stream",
        &fixture("stream/str_b_strb_mismatch.json"),
    ])
    .assert_code(0)
    .assert_out("partial `strb`")
    .assert_out("MATCH");
}

#[test]
fn a_response_difference_against_a_stream_is_reported() {
    run(&[
        "hci-rsp-vs-stream",
        "--hci",
        &fixture("hci/rsp_a_basic.json"),
        "--stream",
        &fixture("stream/str_b_shorter.json"),
    ])
    .assert_code(1)
    .assert_out("only in A");
}
