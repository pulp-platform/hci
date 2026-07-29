// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Rendering of a comparison.
//!
//! Everything is written into a `&mut dyn Write`, so the report can be rendered
//! into a buffer for tests exactly as it is rendered to the terminal.

use std::io::{self, Write};

use crate::color::Palette;
use crate::compare::{describe, rows_of, Cell, CmpCtx, FieldRow};
use crate::diff::{DiffOp, DiffStats};
use crate::model::{Beat, LoadedLog, NoteLevel};
use crate::value::Value;

const WIDTH: usize = 80;
/// Values wider than this many nibbles are folded over several rows.
const FOLD_NIBBLES: u32 = 16;
/// Columns taken by one folded row: 16 nibbles, `0x`, and 3 separators.
const FOLD_COLS: usize = 21;

#[derive(Debug, Clone)]
pub struct ReportOptions {
    pub context: usize,
    pub max_report: usize,
    pub summary_only: bool,
    pub quiet: bool,
    pub verbose: bool,
    pub ascii: bool,
}

impl Default for ReportOptions {
    fn default() -> Self {
        ReportOptions {
            context: 2,
            max_report: 50,
            summary_only: false,
            quiet: false,
            verbose: false,
            ascii: false,
        }
    }
}

pub struct Section<'a> {
    pub title: &'a str,
    pub a: &'a LoadedLog,
    pub b: &'a LoadedLog,
    pub ctx: &'a CmpCtx,
    pub ops: &'a [DiffOp],
    pub stats: DiffStats,
}

impl Section<'_> {
    pub fn is_match(&self) -> bool {
        self.stats.mismatched == 0 && self.stats.only_a == 0 && self.stats.only_b == 0
    }
}

pub fn render_section(
    w: &mut dyn Write,
    s: &Section<'_>,
    pal: &Palette,
    opts: &ReportOptions,
) -> io::Result<()> {
    if opts.quiet {
        return render_verdict_line(w, s, pal);
    }

    let bar = "=".repeat(WIDTH.saturating_sub(s.title.len() + 4));
    writeln!(w, "{}", pal.hdr(&format!("== {} {}", s.title, bar)))?;
    for (tag, log) in [("A", s.a), ("B", s.b)] {
        writeln!(
            w,
            "  {}  {}   {}   {} transactions",
            pal.meta(tag),
            log.display_name(),
            pal.dim(&log.iface.summary()),
            log.beats.len()
        )?;
    }
    writeln!(w, "  keys      : {}", s.ctx.key_names().join(", "))?;
    writeln!(w, "  ignored   : {}", pal.dim(&s.ctx.ignored_names().join(", ")))?;
    for log in [s.a, s.b] {
        for note in &log.notes {
            match note.level {
                NoteLevel::Warn => writeln!(w, "  {} {}", pal.warn("warning   :"), note.text)?,
                NoteLevel::Info => writeln!(w, "  note      : {}", pal.dim(&note.text))?,
            }
        }
    }
    if s.stats.degraded {
        writeln!(
            w,
            "  {} the two sequences are too different to align exactly; \
             they were compared position by position. Raise --max-diff to try harder.",
            pal.warn("warning   :")
        )?;
    }
    writeln!(w)?;

    if s.is_match() {
        writeln!(
            w,
            "  {}  {}/{} transactions match",
            pal.good("ok"),
            s.stats.matched,
            s.a.beats.len().max(s.b.beats.len())
        )?;
        render_verdict_line(w, s, pal)?;
        return writeln!(w);
    }

    if !opts.summary_only {
        render_differences(w, s, pal, opts)?;
    }
    render_summary_table(w, s, pal, opts)?;
    render_verdict_line(w, s, pal)?;
    writeln!(w)
}

fn render_differences(
    w: &mut dyn Write,
    s: &Section<'_>,
    pal: &Palette,
    opts: &ReportOptions,
) -> io::Result<()> {
    let mut shown = 0usize;
    let mut skipped = 0usize;
    let mut prev_equal: Option<DiffOp> = None;

    for (i, op) in s.ops.iter().enumerate() {
        if let DiffOp::Equal { .. } = op {
            prev_equal = Some(*op);
            continue;
        }
        if opts.max_report > 0 && shown >= opts.max_report {
            skipped += 1;
            continue;
        }
        // Leading context, only at the start of a group of differences.
        if let Some(DiffOp::Equal { a, b, len }) = prev_equal.take() {
            let n = opts.context.min(len);
            for j in (len - n)..len {
                render_context(w, s, pal, a + j, b + j)?;
            }
        }
        match op {
            DiffOp::Replace { a, b } => render_replace(w, s, pal, opts, *a, *b)?,
            DiffOp::OnlyInA { a } => render_only(w, s, pal, Some(*a), None)?,
            DiffOp::OnlyInB { b } => render_only(w, s, pal, None, Some(*b))?,
            DiffOp::Equal { .. } => unreachable!(),
        }
        shown += 1;
        // Trailing context.
        if let Some(DiffOp::Equal { a, b, len }) = s.ops.get(i + 1) {
            let n = opts.context.min(*len);
            for j in 0..n {
                render_context(w, s, pal, a + j, b + j)?;
            }
            // Consumed here, so the next difference does not repeat it.
            prev_equal = None;
        }
        writeln!(w)?;
    }

    if skipped > 0 {
        writeln!(
            w,
            "  {}",
            pal.dim(&format!(
                "... {skipped} more difference(s) not shown (use --max-report 0 for all) ..."
            ))
        )?;
        writeln!(w)?;
    }
    Ok(())
}

fn render_context(
    w: &mut dyn Write,
    s: &Section<'_>,
    pal: &Palette,
    ai: usize,
    bi: usize,
) -> io::Result<()> {
    // The two beats match, so showing A's payload describes both.
    let a = &s.a.beats[ai];
    let b = &s.b.beats[bi];
    writeln!(
        w,
        "  {}  {}   {}",
        pal.dim("="),
        pal.dim(&format!("{} A cycle={} | B cycle={}", a.label(), a.cycle, b.cycle)),
        pal.dim(&describe(a))
    )
}

fn render_replace(
    w: &mut dyn Write,
    s: &Section<'_>,
    pal: &Palette,
    opts: &ReportOptions,
    ai: usize,
    bi: usize,
) -> io::Result<()> {
    let a = &s.a.beats[ai];
    let b = &s.b.beats[bi];
    writeln!(
        w,
        "  {}  {}  {}",
        pal.bad("x"),
        a.label(),
        pal.bad("value mismatch")
    )?;
    writeln!(
        w,
        "       A seq={} cycle={}        B seq={} cycle={}",
        a.seq, a.cycle, b.seq, b.cycle
    )?;
    let rows = rows_of(a, b, s.ctx);
    let name_w = rows.iter().map(|r| r.name.len()).max().unwrap_or(4).max(5);
    for row in &rows {
        render_row(w, pal, opts, row, name_w)?;
    }
    Ok(())
}

/// A string with colour escapes, plus the number of columns it occupies.
struct Painted {
    text: String,
    cols: usize,
}

impl Painted {
    fn plain(text: String) -> Painted {
        Painted { cols: text.chars().count(), text }
    }

    /// Left-aligned in `w` columns; padding is computed on the visible length,
    /// which is what makes the columns line up in colour mode too.
    fn pad(&self, w: usize) -> String {
        format!("{}{}", self.text, " ".repeat(w.saturating_sub(self.cols)))
    }
}

const VAL_COLS: usize = 26;

fn render_row(
    w: &mut dyn Write,
    pal: &Palette,
    opts: &ReportOptions,
    row: &FieldRow,
    name_w: usize,
) -> io::Result<()> {
    match (&row.a, &row.b) {
        (Cell::Val(va), Cell::Val(vb)) if va.nibble_count().max(vb.nibble_count()) > FOLD_NIBBLES => {
            writeln!(w, "       {:name_w$}", row.name)?;
            render_folded(w, pal, opts, va, vb, row.differs)
        }
        (Cell::Val(va), Cell::Val(vb)) => {
            let (ha, hb) = render_hex_pair(va, vb, pal, row.differs);
            writeln!(
                w,
                "       {:name_w$}  {}  {}",
                row.name,
                ha.pad(VAL_COLS),
                hb.text
            )?;
            if row.differs && !pal.enabled {
                let m = marker(va, vb, opts);
                let line = format!(
                    "       {:name_w$}  {}  {}",
                    "",
                    Painted::plain(m.clone()).pad(VAL_COLS),
                    m
                );
                writeln!(w, "{}", line.trim_end())?;
            }
            Ok(())
        }
        (a, b) => {
            let cells = [a, b].map(|c| {
                let t = cell_text(c);
                if row.differs {
                    Painted { cols: t.chars().count(), text: pal.bad(&t) }
                } else {
                    Painted::plain(t)
                }
            });
            writeln!(
                w,
                "       {:name_w$}  {}  {}",
                row.name,
                cells[0].pad(VAL_COLS),
                cells[1].text
            )
        }
    }
}

fn cell_text(c: &Cell) -> String {
    match c {
        Cell::Val(v) => format!("0x{}", v.to_hex_grouped(4)),
        Cell::Text(t) => t.clone(),
        Cell::Missing => "----".to_string(),
    }
}

/// The two hexadecimal renderings of an aligned value pair, with only the
/// differing nibbles painted.
fn render_hex_pair(a: &Value, b: &Value, pal: &Palette, differs: bool) -> (Painted, Painted) {
    let n = a.nibble_count().max(b.nibble_count()).max(1) as usize;
    let ha = pad_left(&a.to_hex(), n);
    let hb = pad_left(&b.to_hex(), n);
    let flags = if differs {
        a.diff_nibbles_msb_first(b)
    } else {
        vec![false; n]
    };
    (paint_hex(&ha, &flags, pal), paint_hex(&hb, &flags, pal))
}

fn pad_left(s: &str, n: usize) -> String {
    if s.len() >= n {
        s.to_string()
    } else {
        format!("{}{}", "0".repeat(n - s.len()), s)
    }
}

fn paint_hex(hex: &str, flags: &[bool], pal: &Palette) -> Painted {
    let chars: Vec<char> = hex.chars().collect();
    let n = chars.len();
    let mut out = String::from("0x");
    let mut cols = 2;
    for (i, c) in chars.iter().enumerate() {
        if i > 0 && (n - i) % 4 == 0 {
            out.push('_');
            cols += 1;
        }
        let s = c.to_string();
        if flags.get(i).copied().unwrap_or(false) {
            out.push_str(&pal.bad(&s));
        } else {
            out.push_str(&s);
        }
        cols += 1;
    }
    Painted { text: out, cols }
}

/// `^` under each differing nibble, for plain-text output.
fn marker(a: &Value, b: &Value, opts: &ReportOptions) -> String {
    let n = a.nibble_count().max(b.nibble_count()).max(1) as usize;
    let flags = a.diff_nibbles_msb_first(b);
    let hat = if opts.ascii { '^' } else { '^' };
    let mut out = String::from("  ");
    for i in 0..n {
        if i > 0 && (n - i) % 4 == 0 {
            out.push(' ');
        }
        out.push(if flags.get(i).copied().unwrap_or(false) { hat } else { ' ' });
    }
    out
}

/// Wide values (typically `DW = 256`/`512`) folded into 64-bit rows, most
/// significant first, with runs of identical rows elided.
fn render_folded(
    w: &mut dyn Write,
    pal: &Palette,
    opts: &ReportOptions,
    a: &Value,
    b: &Value,
    differs: bool,
) -> io::Result<()> {
    let width = a.width().max(b.width());
    let step = FOLD_NIBBLES * 4;
    let n_rows = (width + step - 1) / step;

    struct Row {
        hi: u32,
        lo: u32,
        a: Value,
        b: Value,
        differs: bool,
    }
    let mut rows = Vec::new();
    for r in (0..n_rows).rev() {
        let lo = r * step;
        let len = step.min(width - lo);
        let sa = a.slice(lo, len);
        let sb = b.slice(lo, len);
        rows.push(Row { hi: lo + len - 1, lo, differs: differs && sa != sb, a: sa, b: sb });
    }

    let mut i = 0;
    while i < rows.len() {
        if rows[i].differs || opts.verbose {
            let r = &rows[i];
            let (ha, hb) = render_hex_pair(&r.a, &r.b, pal, r.differs);
            writeln!(
                w,
                "         A [{:>4}:{:>4}]  {}   B [{:>4}:{:>4}]  {}",
                r.hi,
                r.lo,
                ha.pad(FOLD_COLS),
                r.hi,
                r.lo,
                hb.text
            )?;
            if r.differs && !pal.enabled {
                let m = marker(&r.a, &r.b, opts);
                let line = format!(
                    "                        {}                    {}",
                    Painted::plain(m.clone()).pad(FOLD_COLS),
                    m
                );
                writeln!(w, "{}", line.trim_end())?;
            }
            i += 1;
            continue;
        }
        // Run of identical rows.
        let start = i;
        while i < rows.len() && !rows[i].differs {
            i += 1;
        }
        let run = i - start;
        if run == 1 {
            let r = &rows[start];
            let (ha, hb) = render_hex_pair(&r.a, &r.b, pal, false);
            writeln!(
                w,
                "         A [{:>4}:{:>4}]  {}   B [{:>4}:{:>4}]  {}",
                r.hi,
                r.lo,
                ha.pad(FOLD_COLS),
                r.hi,
                r.lo,
                hb.text
            )?;
        } else {
            writeln!(
                w,
                "         {}",
                pal.dim(&format!("... {run} identical rows elided (use -v to show) ..."))
            )?;
        }
    }
    Ok(())
}

fn render_only(
    w: &mut dyn Write,
    s: &Section<'_>,
    pal: &Palette,
    ai: Option<usize>,
    bi: Option<usize>,
) -> io::Result<()> {
    let (gutter, tag, beat, side): (&str, &str, &Beat, &str) = match (ai, bi) {
        (Some(i), None) => ("-", "only in A", &s.a.beats[i], "A"),
        (None, Some(i)) => ("+", "only in B", &s.b.beats[i], "B"),
        _ => unreachable!(),
    };
    writeln!(
        w,
        "  {}  {}  {}   {} seq={} cycle={}",
        pal.bad(gutter),
        pal.bad(tag),
        beat.label(),
        side,
        beat.seq,
        beat.cycle
    )?;
    writeln!(w, "       {}", describe(beat))?;
    Ok(())
}

fn render_summary_table(
    w: &mut dyn Write,
    s: &Section<'_>,
    pal: &Palette,
    opts: &ReportOptions,
) -> io::Result<()> {
    // (top-left, top-right, bottom-left, bottom-right, horizontal, vertical,
    //  left junction, right junction, cross, top tee, bottom tee)
    let (tl, tr, bl, br, h, v, lj, rj, x, tt, bt) = if opts.ascii {
        ("+", "+", "+", "+", "-", "|", "+", "+", "+", "+", "+")
    } else {
        ("┌", "┐", "└", "┘", "─", "│", "├", "┤", "┼", "┬", "┴")
    };
    let rows = [
        ("total A / B".to_string(), format!("{}/{}", s.a.beats.len(), s.b.beats.len())),
        ("matched".to_string(), s.stats.matched.to_string()),
        ("mismatched".to_string(), s.stats.mismatched.to_string()),
        ("only in A".to_string(), s.stats.only_a.to_string()),
        ("only in B".to_string(), s.stats.only_b.to_string()),
    ];
    let kw = rows.iter().map(|(k, _)| k.len()).max().unwrap();
    let vw = rows.iter().map(|(_, x)| x.len()).max().unwrap().max(9);
    let line = |l: &str, mid: &str, r: &str| {
        format!("  {l}{}{mid}{}{r}", h.repeat(kw + 2), h.repeat(vw + 2))
    };

    writeln!(w, "{}", line(tl, tt, tr))?;
    for (i, (k, val)) in rows.iter().enumerate() {
        if i == 1 {
            writeln!(w, "{}", line(lj, x, rj))?;
        }
        let cell = format!("{val:>vw$}");
        let cell = if (i == 2 && s.stats.mismatched > 0)
            || (i == 3 && s.stats.only_a > 0)
            || (i == 4 && s.stats.only_b > 0)
        {
            pal.bad(&cell)
        } else {
            cell
        };
        writeln!(w, "  {v} {k:kw$} {v} {cell} {v}")?;
    }
    writeln!(w, "{}", line(bl, bt, br))
}

fn render_verdict_line(w: &mut dyn Write, s: &Section<'_>, pal: &Palette) -> io::Result<()> {
    if s.is_match() {
        writeln!(
            w,
            "  {}  {:<34}: {}  ({}/{} transactions)",
            pal.hdr("RESULT"),
            s.title,
            pal.good("MATCH"),
            s.stats.matched,
            s.a.beats.len().max(s.b.beats.len())
        )
    } else {
        writeln!(
            w,
            "  {}  {:<34}: {}  ({} mismatched, {} unmatched)",
            pal.hdr("RESULT"),
            s.title,
            pal.bad("DIFFERENT"),
            s.stats.mismatched,
            s.stats.only_a + s.stats.only_b
        )
    }
}

/// Overall verdict across all sections of a run.
pub fn render_overall(
    w: &mut dyn Write,
    sections: &[Section<'_>],
    pal: &Palette,
) -> io::Result<()> {
    let all_match = sections.iter().all(|s| s.is_match());
    writeln!(
        w,
        "  {}  {}",
        pal.hdr("RESULT"),
        if all_match { pal.good("MATCH") } else { pal.bad("DIFFERENT") }
    )
}

/// `show`: pretty-print a single log.
pub fn render_show(w: &mut dyn Write, log: &LoadedLog, pal: &Palette) -> io::Result<()> {
    writeln!(
        w,
        "{}",
        pal.hdr(&format!("{} log: {}", log.kind.label(), log.file.display()))
    )?;
    writeln!(w, "  path      : {}", log.display_name())?;
    writeln!(w, "  interface : {}", log.iface.summary())?;
    writeln!(w, "  count     : {}", log.beats.len())?;
    for note in &log.notes {
        match note.level {
            NoteLevel::Warn => writeln!(w, "  {} {}", pal.warn("warning   :"), note.text)?,
            NoteLevel::Info => writeln!(w, "  note      : {}", pal.dim(&note.text))?,
        }
    }
    writeln!(w)?;
    for beat in &log.beats {
        writeln!(
            w,
            "  {}  cycle={:<8}  {}",
            beat.label(),
            beat.cycle,
            describe(beat)
        )?;
    }
    Ok(())
}
