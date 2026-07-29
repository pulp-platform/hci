// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Alignment of two transaction sequences.
//!
//! The comparison is on content, not on time, so the two sequences are aligned
//! as *sequences*: an inserted transaction shows up as one insertion rather than
//! shifting everything after it into a cascade of mismatches.
//!
//! Pipeline: intern the keys to `u32`, strip the common prefix and suffix (which
//! is what makes a one-byte difference inside a 100k-transaction trace cheap),
//! run Myers' O(ND) algorithm on what is left, then pair adjacent
//! delete/insert runs into 1:1 `Replace` operations.

use std::collections::HashMap;
use std::hash::Hash;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffOp {
    /// `len` consecutive beats that match, starting at `a`/`b`.
    Equal { a: usize, b: usize, len: usize },
    /// Aligned pair whose content differs.
    Replace { a: usize, b: usize },
    OnlyInA { a: usize },
    OnlyInB { b: usize },
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct DiffStats {
    pub matched: usize,
    pub mismatched: usize,
    pub only_a: usize,
    pub only_b: usize,
    /// The exact alignment was too expensive; a pairwise fallback was used.
    pub degraded: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Edit {
    Equal(usize, usize),
    Delete(usize),
    Insert(usize),
}

/// Align `a` against `b`.
///
/// `max_cost` bounds the edit distance that will be searched exactly; beyond it
/// the two sequences are considered unrelated and are aligned pairwise, with
/// [`DiffStats::degraded`] set so the report can say so.
pub fn diff<T: Hash + Eq>(a: &[T], b: &[T], max_cost: usize) -> (Vec<DiffOp>, DiffStats) {
    let (ia, ib) = intern(a, b);
    diff_interned(&ia, &ib, max_cost)
}

fn intern<T: Hash + Eq>(a: &[T], b: &[T]) -> (Vec<u32>, Vec<u32>) {
    let mut ids: HashMap<&T, u32> = HashMap::with_capacity(a.len() + b.len());
    let mut next = 0u32;
    let mut out_a = Vec::with_capacity(a.len());
    for x in a {
        let id = match ids.get(x) {
            Some(id) => *id,
            None => {
                let id = next;
                next += 1;
                ids.insert(x, id);
                id
            }
        };
        out_a.push(id);
    }
    let mut out_b = Vec::with_capacity(b.len());
    for x in b {
        let id = match ids.get(x) {
            Some(id) => *id,
            None => {
                let id = next;
                next += 1;
                ids.insert(x, id);
                id
            }
        };
        out_b.push(id);
    }
    (out_a, out_b)
}

fn diff_interned(a: &[u32], b: &[u32], max_cost: usize) -> (Vec<DiffOp>, DiffStats) {
    // Common prefix / suffix: the dominant optimization on real traces.
    let mut lo = 0usize;
    while lo < a.len() && lo < b.len() && a[lo] == b[lo] {
        lo += 1;
    }
    let mut hi = 0usize;
    while hi < a.len() - lo && hi < b.len() - lo && a[a.len() - 1 - hi] == b[b.len() - 1 - hi] {
        hi += 1;
    }
    let mid_a = &a[lo..a.len() - hi];
    let mid_b = &b[lo..b.len() - hi];

    let mut edits: Vec<Edit> = Vec::new();
    if lo > 0 {
        for i in 0..lo {
            edits.push(Edit::Equal(i, i));
        }
    }

    let mut degraded = false;
    match myers(mid_a, mid_b, max_cost) {
        Some(mid) => {
            for e in mid {
                edits.push(match e {
                    Edit::Equal(x, y) => Edit::Equal(x + lo, y + lo),
                    Edit::Delete(x) => Edit::Delete(x + lo),
                    Edit::Insert(y) => Edit::Insert(y + lo),
                });
            }
        }
        None => {
            degraded = true;
            let n = mid_a.len().min(mid_b.len());
            for i in 0..n {
                if mid_a[i] == mid_b[i] {
                    edits.push(Edit::Equal(i + lo, i + lo));
                } else {
                    edits.push(Edit::Delete(i + lo));
                    edits.push(Edit::Insert(i + lo));
                }
            }
            for i in n..mid_a.len() {
                edits.push(Edit::Delete(i + lo));
            }
            for i in n..mid_b.len() {
                edits.push(Edit::Insert(i + lo));
            }
        }
    }

    for i in 0..hi {
        edits.push(Edit::Equal(a.len() - hi + i, b.len() - hi + i));
    }

    let mut ops = coalesce(&edits);
    pair_replacements(&mut ops);
    let stats = stats_of(&ops, degraded);
    (ops, stats)
}

/// Myers' O(ND) algorithm with a per-depth snapshot of the frontier, so the
/// path can be walked back exactly. Memory is O(D^2), which is why `max_cost`
/// exists; `None` means the bound was hit.
fn myers(a: &[u32], b: &[u32], max_cost: usize) -> Option<Vec<Edit>> {
    let n = a.len() as isize;
    let m = b.len() as isize;
    if n == 0 && m == 0 {
        return Some(Vec::new());
    }
    let max_d = ((n + m) as usize).min(max_cost);
    let off = (max_d + 1) as isize;
    let size = 2 * max_d + 3;
    let mut v = vec![0isize; size];
    let mut trace: Vec<Vec<isize>> = Vec::new();

    let mut found: Option<usize> = None;
    for d in 0..=max_d {
        let dd = d as isize;
        let mut k = -dd;
        while k <= dd {
            let ki = (off + k) as usize;
            let mut x = if k == -dd || (k != dd && v[ki - 1] < v[ki + 1]) {
                v[ki + 1]
            } else {
                v[ki - 1] + 1
            };
            let mut y = x - k;
            while x < n && y < m && a[x as usize] == b[y as usize] {
                x += 1;
                y += 1;
            }
            v[ki] = x;
            if x >= n && y >= m {
                found = Some(d);
            }
            k += 2;
        }
        // Snapshot only the reachable band.
        let from = (off - dd) as usize;
        let to = (off + dd) as usize;
        trace.push(v[from..=to].to_vec());
        if found.is_some() {
            break;
        }
    }

    let total = found?;
    Some(backtrack(a, b, &trace, total))
}

fn backtrack(a: &[u32], b: &[u32], trace: &[Vec<isize>], total: usize) -> Vec<Edit> {
    // Snapshot for depth d covers k in [-d, d] with offset d.
    let at = |d: usize, k: isize| -> isize { trace[d][(k + d as isize) as usize] };

    let mut out: Vec<Edit> = Vec::new();
    let mut x = a.len() as isize;
    let mut y = b.len() as isize;

    for d in (1..=total).rev() {
        let dd = d as isize;
        let k = x - y;
        let prev_k = if k == -dd {
            k + 1
        } else if k == dd {
            k - 1
        } else if at(d - 1, k - 1) < at(d - 1, k + 1) {
            k + 1
        } else {
            k - 1
        };
        let prev_x = at(d - 1, prev_k);
        let prev_y = prev_x - prev_k;

        while x > prev_x && y > prev_y {
            x -= 1;
            y -= 1;
            out.push(Edit::Equal(x as usize, y as usize));
        }
        if x > prev_x {
            x -= 1;
            out.push(Edit::Delete(x as usize));
        } else {
            y -= 1;
            out.push(Edit::Insert(y as usize));
        }
    }
    while x > 0 && y > 0 {
        x -= 1;
        y -= 1;
        out.push(Edit::Equal(x as usize, y as usize));
    }
    out.reverse();
    out
}

fn coalesce(edits: &[Edit]) -> Vec<DiffOp> {
    let mut ops: Vec<DiffOp> = Vec::new();
    for e in edits {
        match *e {
            Edit::Equal(x, y) => match ops.last_mut() {
                Some(DiffOp::Equal { a, b, len }) if *a + *len == x && *b + *len == y => *len += 1,
                _ => ops.push(DiffOp::Equal { a: x, b: y, len: 1 }),
            },
            Edit::Delete(x) => ops.push(DiffOp::OnlyInA { a: x }),
            Edit::Insert(y) => ops.push(DiffOp::OnlyInB { b: y }),
        }
    }
    ops
}

/// Turn a run of deletions immediately followed (or preceded) by a run of
/// insertions into 1:1 `Replace` pairs, so a changed transaction reads as one
/// mismatch instead of a delete plus an insert.
fn pair_replacements(ops: &mut Vec<DiffOp>) {
    let mut out: Vec<DiffOp> = Vec::with_capacity(ops.len());
    let mut i = 0;
    while i < ops.len() {
        // Collect a maximal run of non-Equal ops.
        let start = i;
        while i < ops.len() && !matches!(ops[i], DiffOp::Equal { .. }) {
            i += 1;
        }
        if i == start {
            out.push(ops[i]);
            i += 1;
            continue;
        }
        let mut dels: Vec<usize> = Vec::new();
        let mut inss: Vec<usize> = Vec::new();
        for op in &ops[start..i] {
            match op {
                DiffOp::OnlyInA { a } => dels.push(*a),
                DiffOp::OnlyInB { b } => inss.push(*b),
                _ => {}
            }
        }
        let paired = dels.len().min(inss.len());
        for j in 0..paired {
            out.push(DiffOp::Replace { a: dels[j], b: inss[j] });
        }
        for a in dels.into_iter().skip(paired) {
            out.push(DiffOp::OnlyInA { a });
        }
        for b in inss.into_iter().skip(paired) {
            out.push(DiffOp::OnlyInB { b });
        }
    }
    *ops = out;
}

fn stats_of(ops: &[DiffOp], degraded: bool) -> DiffStats {
    let mut s = DiffStats { degraded, ..Default::default() };
    for op in ops {
        match op {
            DiffOp::Equal { len, .. } => s.matched += len,
            DiffOp::Replace { .. } => s.mismatched += 1,
            DiffOp::OnlyInA { .. } => s.only_a += 1,
            DiffOp::OnlyInB { .. } => s.only_b += 1,
        }
    }
    s
}

/// Move a `Replace` to `Equal` after the fact.
///
/// Used when the authoritative, pair-aware verdict in [`crate::compare`] finds
/// that two aligned beats do carry the same content even though their alignment
/// keys differed (partial `strb` against an HCI response, `--x-policy=match`).
pub fn downgrade_replace(ops: &mut Vec<DiffOp>, keep: impl Fn(usize, usize) -> bool) -> DiffStats {
    for op in ops.iter_mut() {
        if let DiffOp::Replace { a, b } = *op {
            if keep(a, b) {
                *op = DiffOp::Equal { a, b, len: 1 };
            }
        }
    }
    // Recompute, merging any Equal runs that just became adjacent.
    let mut merged: Vec<DiffOp> = Vec::with_capacity(ops.len());
    for op in ops.iter() {
        match (merged.last_mut(), op) {
            (
                Some(DiffOp::Equal { a, b, len }),
                DiffOp::Equal { a: a2, b: b2, len: len2 },
            ) if *a + *len == *a2 && *b + *len == *b2 => *len += len2,
            _ => merged.push(*op),
        }
    }
    let degraded = false;
    *ops = merged;
    let mut s = stats_of(ops, degraded);
    s.degraded = false;
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(a: &[u32], b: &[u32]) -> (Vec<DiffOp>, DiffStats) {
        diff(a, b, 100_000)
    }

    /// Every op must be consistent: applied to `a` it must reproduce `b`.
    fn check_consistent(a: &[u32], b: &[u32], ops: &[DiffOp]) {
        let mut ai = 0usize;
        let mut bi = 0usize;
        let mut rebuilt: Vec<u32> = Vec::new();
        // Ops are emitted in order; Replace/OnlyIn* consume one element each.
        for op in ops {
            match op {
                DiffOp::Equal { a: x, b: y, len } => {
                    assert_eq!(*x, ai, "A index drift at {op:?}");
                    assert_eq!(*y, bi, "B index drift at {op:?}");
                    for i in 0..*len {
                        assert_eq!(a[x + i], b[y + i]);
                        rebuilt.push(b[y + i]);
                    }
                    ai += len;
                    bi += len;
                }
                DiffOp::Replace { a: x, b: y } => {
                    assert_eq!(*x, ai);
                    assert_eq!(*y, bi);
                    rebuilt.push(b[*y]);
                    ai += 1;
                    bi += 1;
                }
                DiffOp::OnlyInA { a: x } => {
                    assert_eq!(*x, ai);
                    ai += 1;
                }
                DiffOp::OnlyInB { b: y } => {
                    assert_eq!(*y, bi);
                    rebuilt.push(b[*y]);
                    bi += 1;
                }
            }
        }
        assert_eq!(ai, a.len(), "did not consume all of A");
        assert_eq!(bi, b.len(), "did not consume all of B");
        assert_eq!(rebuilt, b, "ops do not reproduce B");
    }

    #[test]
    fn identical_sequences() {
        let a = [1u32, 2, 3, 4, 5];
        let (ops, s) = run(&a, &a);
        assert_eq!(ops, vec![DiffOp::Equal { a: 0, b: 0, len: 5 }]);
        assert_eq!(s.matched, 5);
        assert_eq!((s.mismatched, s.only_a, s.only_b), (0, 0, 0));
    }

    #[test]
    fn both_empty() {
        let (ops, s) = run(&[], &[]);
        assert!(ops.is_empty());
        assert_eq!(s, DiffStats::default());
    }

    #[test]
    fn empty_against_n() {
        let b = [1u32, 2, 3];
        let (ops, s) = run(&[], &b);
        assert_eq!(s.only_b, 3);
        check_consistent(&[], &b, &ops);
        let (ops, s) = run(&b, &[]);
        assert_eq!(s.only_a, 3);
        check_consistent(&b, &[], &ops);
    }

    #[test]
    fn single_replace_is_not_a_delete_plus_insert() {
        let a = [1u32, 2, 3, 4, 5];
        let b = [1u32, 2, 9, 4, 5];
        let (ops, s) = run(&a, &b);
        assert_eq!(s.mismatched, 1);
        assert_eq!(s.matched, 4);
        assert_eq!((s.only_a, s.only_b), (0, 0));
        assert!(ops.contains(&DiffOp::Replace { a: 2, b: 2 }));
        check_consistent(&a, &b, &ops);
    }

    #[test]
    fn insertion_does_not_cascade() {
        let a = [1u32, 2, 3, 4, 5];
        for pos in 0..=a.len() {
            let mut b = a.to_vec();
            b.insert(pos, 99);
            let (ops, s) = run(&a, &b);
            assert_eq!((s.mismatched, s.only_a, s.only_b), (0, 0, 1), "insert at {pos}");
            assert_eq!(s.matched, 5, "insert at {pos}");
            check_consistent(&a, &b, &ops);
        }
    }

    #[test]
    fn deletion_does_not_cascade() {
        let a = [1u32, 2, 3, 4, 5];
        for pos in 0..a.len() {
            let mut b = a.to_vec();
            b.remove(pos);
            let (ops, s) = run(&a, &b);
            assert_eq!((s.mismatched, s.only_a, s.only_b), (0, 1, 0), "delete at {pos}");
            assert_eq!(s.matched, 4, "delete at {pos}");
            check_consistent(&a, &b, &ops);
        }
    }

    #[test]
    fn asymmetric_run_becomes_replaces_plus_leftovers() {
        let a = [1u32, 7, 8, 9, 5];
        let b = [1u32, 70, 5];
        let (ops, s) = run(&a, &b);
        assert_eq!(s.mismatched, 1);
        assert_eq!(s.only_a, 2);
        assert_eq!(s.only_b, 0);
        check_consistent(&a, &b, &ops);
    }

    #[test]
    fn two_separate_hunks() {
        let a = [1u32, 2, 3, 4, 5, 6, 7, 8];
        let b = [1u32, 9, 3, 4, 5, 6, 99, 8];
        let (ops, s) = run(&a, &b);
        assert_eq!(s.mismatched, 2);
        assert_eq!(s.matched, 6);
        check_consistent(&a, &b, &ops);
    }

    #[test]
    fn duplicated_keys_are_not_mispaired() {
        let a = vec![7u32; 20];
        let mut b = vec![7u32; 20];
        b[10] = 8;
        let (ops, s) = run(&a, &b);
        assert_eq!(s.mismatched, 1);
        assert_eq!(s.matched, 19);
        check_consistent(&a, &b, &ops);
    }

    #[test]
    fn long_common_prefix_and_suffix_are_trimmed() {
        let mut a: Vec<u32> = (0..5000).collect();
        let mut b = a.clone();
        a[2500] = 111_111;
        b[2500] = 222_222;
        let (ops, s) = run(&a, &b);
        assert_eq!(s.mismatched, 1);
        assert_eq!(s.matched, 4999);
        check_consistent(&a, &b, &ops);
    }

    #[test]
    fn unrelated_sequences_degrade_instead_of_hanging() {
        let a: Vec<u32> = (0..2000).collect();
        let b: Vec<u32> = (10_000..12_000).collect();
        let (ops, s) = diff(&a, &b, 8);
        assert!(s.degraded);
        assert_eq!(s.mismatched, 2000);
        check_consistent(&a, &b, &ops);
    }

    #[test]
    fn cost_cap_is_not_hit_by_a_small_edit_distance() {
        let a: Vec<u32> = (0..2000).collect();
        let mut b = a.clone();
        b.remove(1000);
        let (_, s) = diff(&a, &b, 8);
        assert!(!s.degraded);
        assert_eq!(s.only_a, 1);
    }

    #[test]
    fn downgrade_turns_a_replace_into_a_merged_equal_run() {
        let a = [1u32, 2, 3];
        let b = [1u32, 9, 3];
        let (mut ops, s) = run(&a, &b);
        assert_eq!(s.mismatched, 1);
        let s2 = downgrade_replace(&mut ops, |_, _| true);
        assert_eq!(ops, vec![DiffOp::Equal { a: 0, b: 0, len: 3 }]);
        assert_eq!(s2.matched, 3);
        assert_eq!(s2.mismatched, 0);
    }
}
