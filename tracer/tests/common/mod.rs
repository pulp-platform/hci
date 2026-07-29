// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Shared harness for the integration tests: run the real binary over the
//! synthetic logs in `tests/fixtures/` and inspect its exit status and output.
//!
//! Each integration test binary compiles this module separately, so not every
//! helper is used by every one of them.
#![allow(dead_code)]

use std::path::PathBuf;
use std::process::Command;

pub struct Output {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Output {
    #[track_caller]
    pub fn assert_code(&self, want: i32) -> &Self {
        assert_eq!(
            self.code, want,
            "expected exit {want}, got {}\n--- stdout ---\n{}\n--- stderr ---\n{}",
            self.code, self.stdout, self.stderr
        );
        self
    }

    #[track_caller]
    pub fn assert_out(&self, needle: &str) -> &Self {
        assert!(
            self.stdout.contains(needle),
            "stdout does not contain {needle:?}\n--- stdout ---\n{}",
            self.stdout
        );
        self
    }

    #[track_caller]
    pub fn assert_not_out(&self, needle: &str) -> &Self {
        assert!(
            !self.stdout.contains(needle),
            "stdout unexpectedly contains {needle:?}\n--- stdout ---\n{}",
            self.stdout
        );
        self
    }

    #[track_caller]
    pub fn assert_err(&self, needle: &str) -> &Self {
        assert!(
            self.stderr.contains(needle),
            "stderr does not contain {needle:?}\n--- stderr ---\n{}",
            self.stderr
        );
        self
    }

    /// Number of `x  #NNNN  value mismatch` entries in the report.
    pub fn mismatch_entries(&self) -> usize {
        self.stdout.matches("value mismatch").count()
    }

    pub fn summary(&self, field: &str) -> usize {
        for line in self.stdout.lines() {
            let t = line.trim_start_matches([' ', '|']).trim();
            if let Some(rest) = t.strip_prefix(field) {
                if let Some(v) = rest.trim_start_matches([' ', '|']).split('|').next() {
                    if let Ok(n) = v.trim().parse::<usize>() {
                        return n;
                    }
                }
            }
        }
        panic!("no summary row `{field}` in\n{}", self.stdout);
    }
}

pub fn fixture(rel: &str) -> String {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("tests/fixtures");
    p.push(rel);
    assert!(p.exists(), "missing fixture {}", p.display());
    p.to_string_lossy().into_owned()
}

/// Run the binary with deterministic, plain-text output settings.
pub fn run(args: &[&str]) -> Output {
    run_raw(&[args, &["--color=never", "--ascii"]].concat())
}

/// Run the binary with exactly the given arguments.
pub fn run_raw(args: &[&str]) -> Output {
    let out = Command::new(env!("CARGO_BIN_EXE_hci-tracer"))
        .args(args)
        .env_remove("NO_COLOR")
        .env_remove("CLICOLOR_FORCE")
        .env("TERM", "dumb")
        .output()
        .expect("failed to run hci-tracer");
    Output {
        code: out.status.code().expect("terminated by a signal"),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}
