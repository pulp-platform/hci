// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Command-line surface.

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand, ValueEnum};

use crate::color::ColorChoice;
use crate::compare::{CompareOptions, XPolicy};
use crate::load::RepairMode;
use crate::report::ReportOptions;
use crate::split::SplitMode;

#[derive(Parser, Debug)]
#[command(
    name = "hci-tracer",
    version,
    about = "Compare HCI-Core and HWPE-Stream transaction logs on content, not on time",
    long_about = "Compare transaction logs produced by the hci_transaction_tracer and \
                  hwpe_stream_transaction_tracer SystemVerilog modules.\n\n\
                  Only the content of valid data -- transactions whose handshake was \
                  satisfied -- is compared; the cycle at which a transaction happened is \
                  reported to help you find it in a waveform, but never compared.\n\n\
                  Exit status: 0 identical, 1 differences found, 2 usage or input error, \
                  4 an input was truncated and --fail-on-truncated was given."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,

    #[command(flatten)]
    pub global: GlobalArgs,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// Compare two HCI logs: requests, responses, or both.
    HciVsHci {
        /// Request log of side A.
        #[arg(long, value_name = "FILE")]
        a_req: Option<PathBuf>,
        /// Response log of side A.
        #[arg(long, value_name = "FILE")]
        a_rsp: Option<PathBuf>,
        /// Request log of side B.
        #[arg(long, value_name = "FILE")]
        b_req: Option<PathBuf>,
        /// Response log of side B.
        #[arg(long, value_name = "FILE")]
        b_rsp: Option<PathBuf>,
        #[command(flatten)]
        cmp: CompareArgs,
    },
    /// Compare the write requests of an HCI log (wen == 0) against a HWPE-Stream.
    HciReqVsStream {
        #[arg(long, value_name = "FILE")]
        hci: PathBuf,
        #[arg(long, value_name = "FILE")]
        stream: PathBuf,
        #[command(flatten)]
        cmp: CompareArgs,
    },
    /// Compare an HCI response log against a HWPE-Stream.
    HciRspVsStream {
        #[arg(long, value_name = "FILE")]
        hci: PathBuf,
        #[arg(long, value_name = "FILE")]
        stream: PathBuf,
        #[command(flatten)]
        cmp: CompareArgs,
    },
    /// Compare two HWPE-Stream logs.
    StreamVsStream {
        #[arg(long, value_name = "FILE")]
        a: PathBuf,
        #[arg(long, value_name = "FILE")]
        b: PathBuf,
        #[command(flatten)]
        cmp: CompareArgs,
    },
    /// Pretty-print a single log; the schema is detected automatically.
    Show {
        #[arg(value_name = "FILE")]
        file: PathBuf,
    },
}

#[derive(Args, Debug, Clone)]
pub struct GlobalArgs {
    /// When to colourize the output.
    #[arg(long, global = true, value_enum, default_value = "auto")]
    pub color: ColorChoiceArg,

    /// Use only ASCII characters for tables and markers.
    #[arg(long, global = true)]
    pub ascii: bool,

    /// Matching transactions to show around each difference.
    #[arg(long, global = true, value_name = "N", default_value_t = 2)]
    pub context: usize,

    /// Stop after this many differences; 0 shows them all.
    #[arg(long, global = true, value_name = "N", default_value_t = 50)]
    pub max_report: usize,

    /// Show only the headers, the summary table and the verdict.
    #[arg(long, global = true)]
    pub summary_only: bool,

    /// Print only the verdict line of each section.
    #[arg(short = 'q', long, global = true)]
    pub quiet: bool,

    /// Show every row of wide values and never elide identical ones.
    #[arg(short = 'v', long, global = true)]
    pub verbose: bool,
}

#[derive(Args, Debug, Clone)]
pub struct CompareArgs {
    /// Compare full data words, without be/strb masking.
    #[arg(long)]
    pub strict_be: bool,

    /// Include user / r_user in the comparison.
    #[arg(long)]
    pub check_user: bool,

    /// Include id / r_id in the comparison.
    #[arg(long)]
    pub check_id: bool,

    /// Include ecc / r_ecc in the comparison.
    #[arg(long)]
    pub check_ecc: bool,

    /// Do not compare request addresses.
    #[arg(long)]
    pub ignore_add: bool,

    /// Do not compare the request direction.
    #[arg(long)]
    pub ignore_wen: bool,

    /// Do not compare be/strb, but keep using them to mask data.
    #[arg(long)]
    pub ignore_en: bool,

    /// Compare a wide log against a narrow one by splitting each wide beat
    /// (little-endian element order). Optionally pin the expected ratio.
    #[arg(
        long,
        value_name = "N|auto",
        num_args = 0..=1,
        require_equals = true,
        default_missing_value = "auto"
    )]
    pub split: Option<SplitMode>,

    /// Drop beats whose enable is all zero.
    #[arg(long)]
    pub drop_empty: bool,

    /// How to treat x/z bits in enabled bytes.
    #[arg(long, value_enum, default_value = "mismatch")]
    pub x_policy: XPolicyArg,

    /// Whether to repair a log cut short by an aborted simulation.
    #[arg(long, value_enum, default_value = "auto")]
    pub repair: RepairArg,

    /// Exit with status 4 if any input had to be repaired.
    #[arg(long)]
    pub fail_on_truncated: bool,

    /// Largest edit distance searched exactly before falling back to a
    /// position-by-position comparison.
    #[arg(long, value_name = "N", default_value_t = 2000)]
    pub max_diff: usize,
}

#[derive(ValueEnum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColorChoiceArg {
    Auto,
    Always,
    Never,
}

#[derive(ValueEnum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum XPolicyArg {
    /// An x/z bit in an enabled byte matches anything.
    Match,
    /// An x/z bit in an enabled byte is a difference.
    Mismatch,
    /// An x/z bit in an enabled byte aborts the run.
    Error,
}

#[derive(ValueEnum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum RepairArg {
    Auto,
    Never,
}

impl From<ColorChoiceArg> for ColorChoice {
    fn from(v: ColorChoiceArg) -> Self {
        match v {
            ColorChoiceArg::Auto => ColorChoice::Auto,
            ColorChoiceArg::Always => ColorChoice::Always,
            ColorChoiceArg::Never => ColorChoice::Never,
        }
    }
}

impl From<XPolicyArg> for XPolicy {
    fn from(v: XPolicyArg) -> Self {
        match v {
            XPolicyArg::Match => XPolicy::Match,
            XPolicyArg::Mismatch => XPolicy::Mismatch,
            XPolicyArg::Error => XPolicy::Error,
        }
    }
}

impl From<RepairArg> for RepairMode {
    fn from(v: RepairArg) -> Self {
        match v {
            RepairArg::Auto => RepairMode::Auto,
            RepairArg::Never => RepairMode::Never,
        }
    }
}

impl CompareArgs {
    pub fn options(&self) -> CompareOptions {
        CompareOptions {
            strict_be: self.strict_be,
            check_user: self.check_user,
            check_id: self.check_id,
            check_ecc: self.check_ecc,
            ignore_add: self.ignore_add,
            ignore_wen: self.ignore_wen,
            ignore_en: self.ignore_en,
            x: self.x_policy.into(),
        }
    }
}

impl GlobalArgs {
    pub fn report_options(&self) -> ReportOptions {
        ReportOptions {
            context: self.context,
            max_report: self.max_report,
            summary_only: self.summary_only,
            quiet: self.quiet,
            verbose: self.verbose,
            ascii: self.ascii,
        }
    }
}

impl Command {
    pub fn compare_args(&self) -> Option<&CompareArgs> {
        match self {
            Command::HciVsHci { cmp, .. }
            | Command::HciReqVsStream { cmp, .. }
            | Command::HciRspVsStream { cmp, .. }
            | Command::StreamVsStream { cmp, .. } => Some(cmp),
            Command::Show { .. } => None,
        }
    }
}
