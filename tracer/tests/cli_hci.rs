// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! `hci-vs-hci`: comparing two HCI transaction logs, requests and responses.

mod common;

use common::{fixture, run};

fn req_pair(a: &str, b: &str) -> [String; 4] {
    ["--a-req".into(), fixture(a), "--b-req".into(), fixture(b)]
}

fn args(v: &[String]) -> Vec<&str> {
    let mut out = vec!["hci-vs-hci"];
    out.extend(v.iter().map(|s| s.as_str()));
    out
}

#[test]
fn identical_requests_and_responses_match() {
    let out = run(&[
        "hci-vs-hci",
        "--a-req",
        &fixture("hci/req_a_basic.json"),
        "--b-req",
        &fixture("hci/req_b_basic.json"),
        "--a-rsp",
        &fixture("hci/rsp_a_basic.json"),
        "--b-rsp",
        &fixture("hci/rsp_b_basic.json"),
    ]);
    out.assert_code(0)
        .assert_out("== HCI request")
        .assert_out("== HCI response")
        .assert_out("8/8 transactions match")
        .assert_out("RESULT  MATCH");
}

#[test]
fn shifting_every_cycle_changes_nothing() {
    // The whole point: content is compared, time is not.
    run(&[
        "hci-vs-hci",
        "--a-rsp",
        &fixture("hci/rsp_a_basic.json"),
        "--b-rsp",
        &fixture("hci/rsp_a_cycle_shift.json"),
    ])
    .assert_code(0)
    .assert_out("MATCH");
}

#[test]
fn a_single_changed_nibble_is_one_mismatch() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_one_mismatch.json");
    let out = run(&args(&p));
    out.assert_code(1).assert_out("value mismatch").assert_out("data&be");
    assert_eq!(out.mismatch_entries(), 1);
    assert_eq!(out.summary("mismatched"), 1);
    assert_eq!(out.summary("only in A"), 0);
    assert_eq!(out.summary("only in B"), 0);
    assert_eq!(out.summary("matched"), 7);
}

#[test]
fn the_differing_nibble_is_marked() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_one_mismatch.json");
    let out = run(&args(&p));
    // 0xdead_4444 vs 0xdead_4044: exactly one nibble, so exactly one caret.
    let marker = out
        .stdout
        .lines()
        .find(|l| l.trim_start().starts_with('^'))
        .expect("no marker row");
    assert_eq!(marker.matches('^').count(), 2, "one caret per side: {marker:?}");
}

#[test]
fn an_extra_transaction_in_b_does_not_cascade() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_extra_tx.json");
    let out = run(&args(&p));
    out.assert_code(1).assert_out("only in B");
    assert_eq!(out.summary("only in B"), 1);
    assert_eq!(out.summary("mismatched"), 0);
    assert_eq!(out.summary("matched"), 8);
}

#[test]
fn an_extra_transaction_in_a_does_not_cascade() {
    let p = req_pair("hci/req_a_extra_tx.json", "hci/req_b_basic.json");
    let out = run(&args(&p));
    out.assert_code(1).assert_out("only in A");
    assert_eq!(out.summary("only in A"), 1);
    assert_eq!(out.summary("mismatched"), 0);
}

#[test]
fn disabled_bytes_are_dont_care_by_default_and_compared_with_strict_be() {
    let p = req_pair("hci/req_a_be_dontcare.json", "hci/req_b_be_dontcare.json");
    run(&args(&p)).assert_code(0).assert_out("MATCH");

    let mut strict = args(&p);
    strict.push("--strict-be");
    run(&strict).assert_code(1).assert_out("DIFFERENT");
}

#[test]
fn bank_width_interfaces_work() {
    // BW = 32: one enable bit per 32-bit word.
    let p = req_pair("hci/req_a_bw32.json", "hci/req_b_bw32.json");
    run(&args(&p)).assert_code(0).assert_out("DW=128 AW=32 BW=32");
}

#[test]
fn wide_data_is_folded_and_identical_rows_are_elided() {
    let p = req_pair("hci/req_a_wide512.json", "hci/req_b_wide512.json");
    let out = run(&args(&p));
    out.assert_code(1)
        .assert_out("DW=512")
        .assert_out("[ 127:  64]")
        .assert_out("identical rows elided");
    assert_eq!(out.summary("mismatched"), 1);

    let mut verbose = args(&p);
    verbose.push("-v");
    run(&verbose).assert_code(1).assert_not_out("identical rows elided");
}

#[test]
fn response_opcodes_are_compared_and_sections_are_independent() {
    let out = run(&[
        "hci-vs-hci",
        "--a-req",
        &fixture("hci/req_a_basic.json"),
        "--b-req",
        &fixture("hci/req_b_basic.json"),
        "--a-rsp",
        &fixture("hci/rsp_a_basic.json"),
        "--b-rsp",
        &fixture("hci/rsp_b_opc_mismatch.json"),
    ]);
    out.assert_code(1)
        .assert_out("r_opc")
        .assert_out("HCI request                       : MATCH")
        .assert_out("HCI response                      : DIFFERENT")
        .assert_out("RESULT  DIFFERENT");
}

#[test]
fn x_in_an_enabled_byte_is_a_difference_but_in_a_disabled_one_is_not() {
    let p = req_pair("hci/req_a_xcase.json", "hci/req_b_xcase.json");
    let out = run(&args(&p));
    // Transaction 0 has an x in an enabled byte; transaction 1 has one in a
    // byte that `be` disables, and must not be flagged.
    out.assert_code(1).assert_out("x/z bits in");
    assert_eq!(out.mismatch_entries(), 1);
    assert_eq!(out.summary("matched"), 1);

    let mut lenient = args(&p);
    lenient.extend(["--x-policy", "match"]);
    run(&lenient).assert_code(0);

    let mut strict = args(&p);
    strict.extend(["--x-policy", "error"]);
    run(&strict).assert_code(2).assert_err("x/z bits in the enabled part");
}

#[test]
fn side_channels_are_off_by_default_and_can_be_switched_on() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_basic.json");
    run(&args(&p)).assert_code(0).assert_out("ignored   : cycle, seq, user, id, ecc");

    let mut with_id = args(&p);
    with_id.push("--check-id");
    run(&with_id).assert_code(0).assert_out("keys      : add, wen, be, data&be, id");
}

#[test]
fn ignore_add_drops_the_address_from_the_key() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_basic.json");
    let mut a = args(&p);
    a.push("--ignore-add");
    run(&a).assert_code(0).assert_out("keys      : wen, be, data&be");
}

#[test]
fn quiet_and_summary_only_shrink_the_report() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_one_mismatch.json");
    let mut q = args(&p);
    q.push("--quiet");
    run(&q).assert_code(1).assert_not_out("value mismatch").assert_out("RESULT");

    let mut s = args(&p);
    s.push("--summary-only");
    run(&s)
        .assert_code(1)
        .assert_not_out("value mismatch")
        .assert_out("mismatched");
}

#[test]
fn max_report_truncates_the_list_of_differences() {
    // Every transaction differs when the two logs are unrelated payloads.
    let out = run(&[
        "hci-vs-hci",
        "--a-req",
        &fixture("hci/req_a_be_dontcare.json"),
        "--b-req",
        &fixture("hci/req_b_be_dontcare.json"),
        "--strict-be",
        "--max-report",
        "1",
    ]);
    out.assert_code(1).assert_out("more difference(s) not shown");
    assert_eq!(out.mismatch_entries(), 1);
}

#[test]
fn the_report_matches_its_golden_copy() {
    let p = req_pair("hci/req_a_basic.json", "hci/req_b_one_mismatch.json");
    let out = run(&args(&p));
    let want = include_str!("expected/req_one_mismatch.txt");
    // Paths appear in warnings only, so the golden copy is machine-independent.
    assert_eq!(out.stdout, want, "report drifted from tests/expected/req_one_mismatch.txt");
}
