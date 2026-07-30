// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Wiring: turn parsed arguments into a rendered comparison and an exit code.

use std::io::Write;
use std::path::Path;

use crate::cli::{Cli, Command, CompareArgs};
use crate::color::{use_color, Palette, RealEnv};
use crate::compare::{
    beats_equal, check_side_channels, check_unknowns, key_of, keep_writes, CmpCtx, Mode, Side,
};
use crate::diff::{diff, downgrade_replace, DiffOp, DiffStats};
use crate::error::{Error, Result};
use crate::load::{load_hci_request, load_hci_response, load_hwpe_stream, probe_kind, RepairMode};
use crate::model::{LoadedLog, LogKind, Note};
use crate::report::{render_overall, render_section, render_show, Section};
use crate::split::normalize_widths;

/// Exit codes, as documented in the CLI help.
pub const EXIT_MATCH: i32 = 0;
pub const EXIT_DIFFERENT: i32 = 1;
pub const EXIT_TRUNCATED: i32 = 4;

/// One rendered comparison: owns its logs so [`Section`] can borrow them.
struct Comparison {
    title: String,
    a: LoadedLog,
    b: LoadedLog,
    ctx: CmpCtx,
    ops: Vec<DiffOp>,
    stats: DiffStats,
}

pub fn run(cli: &Cli, out: &mut dyn Write, out_is_tty: bool) -> Result<i32> {
    let color = use_color(cli.global.color.into(), out_is_tty, &RealEnv);
    let pal = Palette::new(color);
    let opts = cli.global.report_options();

    if let Command::Show { file } = &cli.command {
        let log = load_any(file, RepairMode::Auto)?;
        render_show(out, &log, &pal).map_err(|e| Error::io(file, e))?;
        return Ok(EXIT_MATCH);
    }

    let cmp = cli.command.compare_args().expect("show is handled above");
    let comparisons = build_comparisons(&cli.command, cmp)?;

    let sections: Vec<Section<'_>> = comparisons
        .iter()
        .map(|c| Section {
            title: &c.title,
            a: &c.a,
            b: &c.b,
            ctx: &c.ctx,
            ops: &c.ops,
            stats: c.stats,
        })
        .collect();

    for s in &sections {
        render_section(out, s, &pal, &opts).map_err(io_err)?;
    }
    if sections.len() > 1 {
        render_overall(out, &sections, &pal).map_err(io_err)?;
    }

    let different = sections.iter().any(|s| !s.is_match());
    let truncated = comparisons.iter().any(|c| c.a.repair.repaired || c.b.repair.repaired);
    Ok(if cmp.fail_on_truncated && truncated {
        EXIT_TRUNCATED
    } else if different {
        EXIT_DIFFERENT
    } else {
        EXIT_MATCH
    })
}

fn io_err(e: std::io::Error) -> Error {
    Error::io(Path::new("<stdout>"), e)
}

fn build_comparisons(command: &Command, cmp: &CompareArgs) -> Result<Vec<Comparison>> {
    let mode: RepairMode = cmp.repair.into();
    match command {
        Command::HciVsHci { a_req, a_rsp, b_req, b_rsp, .. } => {
            match (a_req.is_some(), b_req.is_some()) {
                (true, false) | (false, true) => {
                    return Err(Error::Usage(
                        "--a-req and --b-req must be given together".to_string(),
                    ))
                }
                _ => {}
            }
            match (a_rsp.is_some(), b_rsp.is_some()) {
                (true, false) | (false, true) => {
                    return Err(Error::Usage(
                        "--a-rsp and --b-rsp must be given together".to_string(),
                    ))
                }
                _ => {}
            }
            if a_req.is_none() && a_rsp.is_none() {
                return Err(Error::Usage(
                    "give at least one pair of logs to compare: --a-req/--b-req, \
                     --a-rsp/--b-rsp, or both"
                        .to_string(),
                ));
            }
            let mut out = Vec::new();
            if let (Some(fa), Some(fb)) = (a_req, b_req) {
                let a = load_hci_request(fa, mode)?;
                let b = load_hci_request(fb, mode)?;
                out.push(compare(Mode::HciReq, a, b, cmp)?);
            }
            if let (Some(fa), Some(fb)) = (a_rsp, b_rsp) {
                let a = load_hci_response(fa, mode)?;
                let b = load_hci_response(fb, mode)?;
                out.push(compare(Mode::HciRsp, a, b, cmp)?);
            }
            Ok(out)
        }
        Command::HciReqVsStream { hci, stream, .. } => {
            let mut a = load_hci_request(hci, mode)?;
            let b = load_hwpe_stream(stream, mode)?;
            let dropped = keep_writes(&mut a);
            if dropped > 0 {
                a.notes.push(Note::info(format!(
                    "{dropped} load request(s) (wen=1) were left out: a HWPE-Stream \
                     carries no read requests"
                )));
            }
            Ok(vec![compare(Mode::ReqVsStream, a, b, cmp)?])
        }
        Command::HciRspVsStream { hci, stream, .. } => {
            let a = load_hci_response(hci, mode)?;
            let b = load_hwpe_stream(stream, mode)?;
            Ok(vec![compare(Mode::RspVsStream, a, b, cmp)?])
        }
        Command::StreamVsStream { a, b, .. } => {
            let a = load_hwpe_stream(a, mode)?;
            let b = load_hwpe_stream(b, mode)?;
            Ok(vec![compare(Mode::StreamVsStream, a, b, cmp)?])
        }
        Command::Show { .. } => Ok(Vec::new()),
    }
}

fn compare(mode: Mode, mut a: LoadedLog, mut b: LoadedLog, args: &CompareArgs) -> Result<Comparison> {
    let width = normalize_widths(&mut a, &mut b, args.split, args.drop_empty)?;
    let ctx = CmpCtx::new(mode, &a, &b, width, args.options());

    check_side_channels(&a, &b, &ctx)?;
    check_unknowns(&a, Side::A, &ctx)?;
    check_unknowns(&b, Side::B, &ctx)?;

    let keys_a: Vec<_> = a.beats.iter().map(|x| key_of(x, Side::A, &ctx)).collect();
    let keys_b: Vec<_> = b.beats.iter().map(|x| key_of(x, Side::B, &ctx)).collect();

    let (mut ops, mut stats) = diff(&keys_a, &keys_b, args.max_diff);

    // The alignment key is a heuristic; `beats_equal` is the authority. It can
    // only ever be more permissive, so this pass only downgrades mismatches.
    let degraded = stats.degraded;
    let has_replace = ops.iter().any(|op| matches!(op, DiffOp::Replace { .. }));
    if has_replace {
        let (ba, bb) = (&a.beats, &b.beats);
        stats = downgrade_replace(&mut ops, |ai, bi| beats_equal(&ba[ai], &bb[bi], &ctx));
        stats.degraded = degraded;
    }

    Ok(Comparison { title: mode.label().to_string(), a, b, ctx, ops, stats })
}

fn load_any(file: &Path, mode: RepairMode) -> Result<LoadedLog> {
    match probe_kind(file)? {
        LogKind::HciRequest => load_hci_request(file, mode),
        LogKind::HciResponse => load_hci_response(file, mode),
        LogKind::HwpeStream => load_hwpe_stream(file, mode),
    }
}
