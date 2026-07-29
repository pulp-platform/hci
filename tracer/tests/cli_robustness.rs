// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Behaviour on truncated, malformed and misused inputs, and colour policy.

mod common;

use common::{fixture, run, run_raw};

fn vs_b(a: &str) -> Vec<String> {
    vec![
        "hci-vs-hci".into(),
        "--a-req".into(),
        fixture(a),
        "--b-req".into(),
        fixture("hci/req_b_basic.json"),
    ]
}

fn refs(v: &[String]) -> Vec<&str> {
    v.iter().map(|s| s.as_str()).collect()
}

#[test]
fn a_log_cut_mid_transaction_is_repaired_and_the_loss_is_reported() {
    let a = vs_b("hci/req_truncated_midobj.json");
    let out = run(&refs(&a));
    out.assert_code(1)
        .assert_out("was cut short and has been auto-repaired")
        .assert_out("dropping one partially written transaction");
    // Five complete transactions survived; the rest is simply missing.
    assert_eq!(out.summary("matched"), 5);
    assert_eq!(out.summary("mismatched"), 0);
    assert_eq!(out.summary("only in B"), 3);
}

#[test]
fn a_log_cut_after_a_comma_loses_nothing() {
    let a = vs_b("hci/req_truncated_after_comma.json");
    run(&refs(&a)).assert_code(0).assert_out("auto-repaired").assert_out("MATCH");
}

#[test]
fn fail_on_truncated_turns_a_repair_into_a_failure() {
    let mut a = vs_b("hci/req_truncated_after_comma.json");
    a.push("--fail-on-truncated".into());
    run(&refs(&a)).assert_code(4).assert_out("MATCH");
}

#[test]
fn repair_never_surfaces_the_parse_error() {
    let mut a = vs_b("hci/req_truncated_midobj.json");
    a.push("--repair=never".into());
    run(&refs(&a)).assert_code(2).assert_err("EOF while parsing");
}

#[test]
fn a_log_cut_before_the_header_ended_cannot_be_salvaged() {
    let a = vs_b("hci/req_truncated_no_interface.json");
    run(&refs(&a))
        .assert_code(2)
        .assert_err("cut short and could not be repaired")
        .assert_err("header");
}

#[test]
fn an_unrecognized_schema_tag_is_named() {
    let a = vs_b("malformed/bad_schema_tag.json");
    run(&refs(&a)).assert_code(2).assert_err("hci_transaction_bogus-v9");
}

#[test]
fn passing_the_wrong_kind_of_log_says_which_kind_it_is() {
    let a = vs_b("hci/rsp_a_basic.json");
    run(&refs(&a))
        .assert_code(2)
        .assert_err("expected a log with schema `hci_transaction_request-v1`")
        .assert_err("this is an HCI *response* log");
}

#[test]
fn a_missing_interface_is_an_error() {
    let a = vs_b("malformed/missing_interface.json");
    run(&refs(&a)).assert_code(2).assert_err("interface");
}

#[test]
fn an_inconsistent_interface_is_an_error() {
    let a = vs_b("malformed/dw_not_multiple_of_bw.json");
    run(&refs(&a)).assert_code(2).assert_err("BW must divide DW");
}

#[test]
fn an_empty_file_is_an_error() {
    let a = vs_b("malformed/empty.json");
    run(&refs(&a)).assert_code(2);
}

#[test]
fn incomplete_argument_pairs_are_refused() {
    run(&["hci-vs-hci", "--a-req", &fixture("hci/req_a_basic.json")])
        .assert_code(2)
        .assert_err("must be given together");
    run(&["hci-vs-hci"]).assert_code(2).assert_err("at least one pair");
}

#[test]
fn colour_is_off_through_a_pipe_and_on_when_asked_for() {
    let args = [
        "hci-vs-hci",
        "--a-req",
        &fixture("hci/req_a_basic.json"),
        "--b-req",
        &fixture("hci/req_b_one_mismatch.json"),
    ]
    .map(String::from);
    let a = refs(&args);

    let caret_rows = |s: &str| s.lines().filter(|l| l.trim_start().starts_with('^')).count();

    // Not a terminal, so `auto` means plain -- and plain output needs carets.
    let plain = run_raw(&[a.clone(), vec!["--color=auto"]].concat());
    plain.assert_code(1);
    assert!(!plain.stdout.contains('\x1b'), "auto colourized a pipe");
    assert_eq!(caret_rows(&plain.stdout), 1);

    let colored = run_raw(&[a.clone(), vec!["--color=always"]].concat());
    colored.assert_code(1);
    assert!(colored.stdout.contains("\x1b["), "--color=always produced no escapes");
    // With colour the differing nibbles are painted, so the caret row is dropped.
    assert_eq!(caret_rows(&colored.stdout), 0);

    let never = run_raw(&[a, vec!["--color=never"]].concat());
    assert!(!never.stdout.contains('\x1b'));
}

#[test]
fn the_help_documents_the_exit_codes() {
    let out = run_raw(&["--help"]);
    out.assert_code(0)
        .assert_out("0 identical")
        .assert_out("1 differences found")
        .assert_out("4 an input was truncated");
}
