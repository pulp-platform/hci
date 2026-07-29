// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Arbitrary-width unsigned bit vectors with per-bit "unknown" (x/z) tracking.
//!
//! HCI interfaces routinely carry `DW = 256` or `512`, so no field can be held
//! in a `u64`. Every traced field -- `add`, `data`, `be`, `strb`, `r_data`,
//! `user`, `id`, `ecc` -- is represented by [`Value`].
//!
//! Equality and hashing deliberately ignore the declared `width`: only the
//! numeric content matters, so `"0xf"` read as 4 bits and `"0x0000000f"` read
//! as 32 bits are the same value. `width` is kept for formatting only.

use std::fmt;
use std::hash::{Hash, Hasher};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValueError {
    /// No hexadecimal digit at all.
    Empty,
    /// A character that is neither a hex digit nor `x`/`z`/`_`.
    BadChar(char),
    /// The value does not fit in the declared width.
    TooWide { width: u32, significant: u32 },
    /// A zero-width field was requested.
    ZeroWidth,
}

impl fmt::Display for ValueError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ValueError::Empty => write!(f, "no hexadecimal digits"),
            ValueError::BadChar(c) => write!(f, "unexpected character `{c}` in a hexadecimal value"),
            ValueError::TooWide { width, significant } => write!(
                f,
                "value needs {significant} bits but the interface declares only {width}"
            ),
            ValueError::ZeroWidth => write!(f, "zero-width field"),
        }
    }
}

/// One nibble of a [`Value`], as rendered.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Nib {
    Hex(u8),
    /// At least one bit of the nibble was x/z in the simulator.
    X,
}

/// An unsigned value of `width` bits, little-endian byte order.
///
/// Invariant: `bits.len() == unknown.len() == ceil(width/8)` and every bit at
/// index `>= width` is zero in both arrays.
#[derive(Debug, Clone)]
pub struct Value {
    width: u32,
    bits: Box<[u8]>,
    unknown: Box<[u8]>,
}

fn n_bytes(width: u32) -> usize {
    ((width as usize) + 7) / 8
}

fn get_bit(buf: &[u8], i: u32) -> bool {
    let byte = (i / 8) as usize;
    byte < buf.len() && (buf[byte] >> (i % 8)) & 1 == 1
}

fn set_bit(buf: &mut [u8], i: u32) {
    let byte = (i / 8) as usize;
    if byte < buf.len() {
        buf[byte] |= 1 << (i % 8);
    }
}

impl Value {
    pub fn zeros(width: u32) -> Value {
        Value {
            width,
            bits: vec![0u8; n_bytes(width)].into_boxed_slice(),
            unknown: vec![0u8; n_bytes(width)].into_boxed_slice(),
        }
    }

    /// All `width` bits set, and nothing unknown.
    pub fn ones(width: u32) -> Value {
        let mut v = Value::zeros(width);
        for i in 0..width {
            set_bit(&mut v.bits, i);
        }
        v
    }

    pub fn from_u64(value: u64, width: u32) -> Value {
        let mut v = Value::zeros(width);
        for i in 0..width.min(64) {
            if (value >> i) & 1 == 1 {
                set_bit(&mut v.bits, i);
            }
        }
        v
    }

    /// Parse a hexadecimal string as produced by `$fwrite("%h", ...)`.
    ///
    /// Tolerated: leading/trailing whitespace, an optional `0x`/`0X` or
    /// `<size>'h` prefix, `_` group separators, upper or lower case, and `x`/`z`
    /// nibbles (each marking four bits unknown). A bare `x` or `z` marks the
    /// whole value unknown.
    pub fn parse_hex(s: &str, width: u32) -> Result<Value, ValueError> {
        if width == 0 {
            return Err(ValueError::ZeroWidth);
        }
        let s = s.trim();
        // Strip an SV-style `<size>'h` / `'h` prefix, else an `0x` prefix.
        let body = match s.find('\'') {
            Some(pos) => {
                let rest = &s[pos + 1..];
                match rest.chars().next() {
                    Some('h') | Some('H') => &rest[1..],
                    // `'x` / `'z` and friends: keep the payload as digits.
                    _ => rest,
                }
            }
            None => s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")).unwrap_or(s),
        };

        let digits: Vec<char> = body.chars().filter(|c| *c != '_').collect();
        if digits.is_empty() {
            return Err(ValueError::Empty);
        }

        // A bare `x`/`z` means the whole value is unknown.
        if digits.len() == 1 && matches!(digits[0], 'x' | 'X' | 'z' | 'Z') {
            let mut v = Value::zeros(width);
            for i in 0..width {
                set_bit(&mut v.unknown, i);
            }
            return Ok(v);
        }

        let cap = n_bytes(width).max((digits.len() + 1) / 2 + 1);
        let mut bits = vec![0u8; cap];
        let mut unknown = vec![0u8; cap];
        for (i, c) in digits.iter().rev().enumerate() {
            let base = (i as u32) * 4;
            match c {
                '0'..='9' | 'a'..='f' | 'A'..='F' => {
                    let d = c.to_digit(16).unwrap() as u8;
                    for b in 0..4 {
                        if (d >> b) & 1 == 1 {
                            set_bit(&mut bits, base + b);
                        }
                    }
                }
                'x' | 'X' | 'z' | 'Z' => {
                    for b in 0..4 {
                        set_bit(&mut unknown, base + b);
                    }
                }
                other => return Err(ValueError::BadChar(*other)),
            }
        }

        // Anything above `width` must be zero, otherwise the log disagrees with
        // the interface parameters it declares.
        let mut significant = 0u32;
        for i in 0..(cap as u32) * 8 {
            if get_bit(&bits, i) || get_bit(&unknown, i) {
                significant = i + 1;
            }
        }
        if significant > width {
            return Err(ValueError::TooWide { width, significant });
        }

        bits.truncate(n_bytes(width));
        unknown.truncate(n_bytes(width));
        Ok(Value { width, bits: bits.into_boxed_slice(), unknown: unknown.into_boxed_slice() })
    }

    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn nibble_count(&self) -> u32 {
        (self.width + 3) / 4
    }

    pub fn test_bit(&self, i: u32) -> bool {
        get_bit(&self.bits, i)
    }

    pub fn test_unknown(&self, i: u32) -> bool {
        get_bit(&self.unknown, i)
    }

    /// Nibble `i`, counted from the least significant one.
    pub fn nibble(&self, i: u32) -> Nib {
        let base = i * 4;
        let mut d = 0u8;
        for b in 0..4 {
            if get_bit(&self.unknown, base + b) {
                return Nib::X;
            }
            if get_bit(&self.bits, base + b) {
                d |= 1 << b;
            }
        }
        Nib::Hex(d)
    }

    pub fn is_zero(&self) -> bool {
        self.bits.iter().all(|b| *b == 0) && self.unknown.iter().all(|b| *b == 0)
    }

    pub fn unknown_count(&self) -> u32 {
        self.unknown.iter().map(|b| b.count_ones()).sum()
    }

    /// Number of bytes that carry any information, for width-agnostic equality.
    fn significant_bytes(&self) -> usize {
        let mut n = 0;
        for i in 0..self.bits.len() {
            if self.bits[i] != 0 || self.unknown[i] != 0 {
                n = i + 1;
            }
        }
        n
    }

    /// Interpret `self` as a byte/element enable (`be` or `strb`) and expand it
    /// into an `out_width`-wide bit mask, where bit `i` of `self` covers
    /// `elem_bits` consecutive data bits.
    ///
    /// This is what makes `BW = 8, be = 0xf` compare equal to
    /// `ELEMENT_WIDTH = 4, strb = 0xff` on a 32-bit bus: both describe the same
    /// 32 enabled data bits.
    pub fn expand_enable(&self, elem_bits: u32, out_width: u32) -> Result<Value, ValueError> {
        if elem_bits == 0 || out_width == 0 || out_width % elem_bits != 0 {
            return Err(ValueError::TooWide { width: out_width, significant: elem_bits });
        }
        let n_elem = out_width / elem_bits;
        let mut out = Value::zeros(out_width);
        for e in 0..n_elem {
            // An unknown enable bit is treated as enabled: better a spurious
            // difference than a silently skipped one.
            if get_bit(&self.bits, e) || get_bit(&self.unknown, e) {
                for b in 0..elem_bits {
                    set_bit(&mut out.bits, e * elem_bits + b);
                }
            }
        }
        Ok(out)
    }

    /// Zero every bit (and clear its unknown flag) where `mask` is 0.
    ///
    /// Clearing the unknown flag is what makes an `x` inside a disabled byte a
    /// genuine don't-care.
    pub fn mask_with(&self, mask: &Value) -> Value {
        let mut out = Value::zeros(self.width);
        for i in 0..self.width {
            if mask.test_bit(i) {
                if get_bit(&self.bits, i) {
                    set_bit(&mut out.bits, i);
                }
                if get_bit(&self.unknown, i) {
                    set_bit(&mut out.unknown, i);
                }
            }
        }
        out
    }

    /// `len` bits starting at bit `lo`.
    pub fn slice(&self, lo: u32, len: u32) -> Value {
        let mut out = Value::zeros(len);
        for i in 0..len {
            if get_bit(&self.bits, lo + i) {
                set_bit(&mut out.bits, i);
            }
            if get_bit(&self.unknown, lo + i) {
                set_bit(&mut out.unknown, i);
            }
        }
        out
    }

    /// Same value re-declared at `width` bits (used to line up two logs whose
    /// address widths differ). Bits above `width` are dropped.
    pub fn resize(&self, width: u32) -> Value {
        let mut out = Value::zeros(width);
        for i in 0..width {
            if get_bit(&self.bits, i) {
                set_bit(&mut out.bits, i);
            }
            if get_bit(&self.unknown, i) {
                set_bit(&mut out.unknown, i);
            }
        }
        out
    }

    /// Wrapping addition of a small constant; used when splitting a wide
    /// request into narrow sub-beats. Unknown bits make the result unknown.
    pub fn add_u64(&self, delta: u64) -> Value {
        if delta == 0 {
            return self.clone();
        }
        if self.unknown_count() > 0 {
            return self.clone();
        }
        let mut out = Value::zeros(self.width);
        let mut carry = delta;
        for i in 0..out.bits.len() {
            let sum = self.bits[i] as u64 + (carry & 0xff);
            out.bits[i] = (sum & 0xff) as u8;
            carry = (carry >> 8) + (sum >> 8);
        }
        // Re-apply the width invariant.
        for i in out.width..(out.bits.len() as u32) * 8 {
            let byte = (i / 8) as usize;
            out.bits[byte] &= !(1 << (i % 8));
        }
        out
    }

    /// Lowercase hex, most significant nibble first, zero padded to the width.
    pub fn to_hex(&self) -> String {
        let n = self.nibble_count().max(1);
        let mut s = String::with_capacity(n as usize);
        for i in (0..n).rev() {
            match self.nibble(i) {
                Nib::Hex(d) => s.push(char::from_digit(d as u32, 16).unwrap()),
                Nib::X => s.push('x'),
            }
        }
        s
    }

    /// Like [`Value::to_hex`], with `_` inserted every `group` nibbles.
    pub fn to_hex_grouped(&self, group: usize) -> String {
        let raw = self.to_hex();
        if group == 0 || raw.len() <= group {
            return raw;
        }
        let chars: Vec<char> = raw.chars().collect();
        let mut out = String::with_capacity(raw.len() + raw.len() / group);
        // Group from the least significant end so the separators line up.
        let lead = chars.len() % group;
        let mut idx = 0;
        if lead > 0 {
            out.extend(&chars[0..lead]);
            idx = lead;
        }
        while idx < chars.len() {
            if !out.is_empty() {
                out.push('_');
            }
            out.extend(&chars[idx..idx + group]);
            idx += group;
        }
        out
    }

    /// Per-nibble difference flags, most significant nibble first, over the
    /// wider of the two values. Used to paint only the differing nibbles.
    pub fn diff_nibbles_msb_first(&self, other: &Value) -> Vec<bool> {
        let n = self.nibble_count().max(other.nibble_count()).max(1);
        (0..n).rev().map(|i| self.nibble_or_zero(i) != other.nibble_or_zero(i)).collect()
    }

    fn nibble_or_zero(&self, i: u32) -> Nib {
        if i < self.nibble_count() {
            self.nibble(i)
        } else {
            Nib::Hex(0)
        }
    }

    /// True when the two values differ *only* in nibbles that are unknown on at
    /// least one side. Used by `--x-policy=match`.
    pub fn differs_only_by_unknown(&self, other: &Value) -> bool {
        let n = self.nibble_count().max(other.nibble_count()).max(1);
        let mut saw_unknown = false;
        for i in 0..n {
            let (a, b) = (self.nibble_or_zero(i), other.nibble_or_zero(i));
            if a == b {
                continue;
            }
            if a == Nib::X || b == Nib::X {
                saw_unknown = true;
            } else {
                return false;
            }
        }
        saw_unknown
    }
}

impl PartialEq for Value {
    fn eq(&self, other: &Self) -> bool {
        let n = self.significant_bytes().max(other.significant_bytes());
        for i in 0..n {
            let (ab, bb) = (self.bits.get(i).copied().unwrap_or(0), other.bits.get(i).copied().unwrap_or(0));
            let (au, bu) =
                (self.unknown.get(i).copied().unwrap_or(0), other.unknown.get(i).copied().unwrap_or(0));
            if ab != bb || au != bu {
                return false;
            }
        }
        true
    }
}

impl Eq for Value {}

impl Hash for Value {
    fn hash<H: Hasher>(&self, state: &mut H) {
        let n = self.significant_bytes();
        state.write_u32(n as u32);
        state.write(&self.bits[..n]);
        state.write(&self.unknown[..n]);
    }
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "0x{}", self.to_hex())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::hash_map::DefaultHasher;

    fn hash_of(v: &Value) -> u64 {
        let mut h = DefaultHasher::new();
        v.hash(&mut h);
        h.finish()
    }

    #[test]
    fn parses_the_shapes_the_tracer_and_humans_produce() {
        let expect = Value::parse_hex("0xdeadbeef", 32).unwrap();
        for s in ["0xdeadbeef", "deadbeef", "DEADBEEF", "dead_beef", "0xDEAD_beef", "32'hdeadbeef", "'hdeadbeef", "  0xdeadbeef  "] {
            assert_eq!(Value::parse_hex(s, 32).unwrap(), expect, "failed on {s}");
        }
    }

    #[test]
    fn leading_zeros_and_width_do_not_affect_identity() {
        let narrow = Value::parse_hex("0xf", 4).unwrap();
        let wide = Value::parse_hex("0x0000000f", 32).unwrap();
        assert_eq!(narrow, wide);
        assert_eq!(hash_of(&narrow), hash_of(&wide));
    }

    #[test]
    fn rejects_values_that_do_not_fit() {
        assert_eq!(
            Value::parse_hex("0x1ff", 8),
            Err(ValueError::TooWide { width: 8, significant: 9 })
        );
        assert!(Value::parse_hex("0x0ff", 8).is_ok());
        assert_eq!(Value::parse_hex("0x", 8), Err(ValueError::Empty));
        assert_eq!(Value::parse_hex("0xg1", 8), Err(ValueError::BadChar('g')));
        assert_eq!(Value::parse_hex("0x1", 0), Err(ValueError::ZeroWidth));
    }

    #[test]
    fn top_byte_is_masked_to_the_declared_width() {
        let v = Value::parse_hex("0xfff", 12).unwrap();
        assert_eq!(v, Value::parse_hex("0x0fff", 16).unwrap());
        assert_eq!(v.to_hex(), "fff");
    }

    #[test]
    fn tracks_unknown_bits_per_nibble() {
        let v = Value::parse_hex("0xdeadbeeX", 32).unwrap();
        assert_eq!(v.nibble(0), Nib::X);
        assert_eq!(v.nibble(1), Nib::Hex(0xe));
        assert_eq!(v.unknown_count(), 4);
        assert_eq!(v.to_hex(), "deadbeex");

        let all = Value::parse_hex("x", 16).unwrap();
        assert_eq!(all.unknown_count(), 16);
        assert_eq!(all.to_hex(), "xxxx");

        let z = Value::parse_hex("0xzz", 8).unwrap();
        assert_eq!(z.unknown_count(), 8);
    }

    #[test]
    fn unknown_is_distinct_from_zero() {
        assert_ne!(Value::parse_hex("0x0", 4).unwrap(), Value::parse_hex("0xx", 4).unwrap());
    }

    #[test]
    fn round_trips_a_512_bit_value() {
        let hex: String = (0..128).map(|i| char::from_digit(i % 16, 16).unwrap()).collect();
        let v = Value::parse_hex(&hex, 512).unwrap();
        assert_eq!(v.width(), 512);
        assert_eq!(v.to_hex(), hex);
        assert_eq!(v.nibble_count(), 128);
    }

    #[test]
    fn expand_enable_canonicalizes_across_element_widths() {
        let be = Value::parse_hex("0xf", 4).unwrap().expand_enable(8, 32).unwrap();
        let strb = Value::parse_hex("0xff", 8).unwrap().expand_enable(4, 32).unwrap();
        assert_eq!(be, strb);
        assert_eq!(be, Value::ones(32));

        let partial = Value::parse_hex("0x5", 4).unwrap().expand_enable(8, 32).unwrap();
        assert_eq!(partial.to_hex(), "00ff00ff");

        // bank-width HCI: BW = 32
        let bank = Value::parse_hex("0x3", 4).unwrap().expand_enable(32, 128).unwrap();
        assert_eq!(bank.to_hex(), "0000000000000000ffffffffffffffff");

        assert!(Value::parse_hex("0x1", 4).unwrap().expand_enable(3, 32).is_err());
    }

    #[test]
    fn mask_with_erases_disabled_bytes_including_their_unknowns() {
        let data = Value::parse_hex("0xdeadbexx", 32).unwrap();
        let mask = Value::parse_hex("0xc", 4).unwrap().expand_enable(8, 32).unwrap();
        let masked = data.mask_with(&mask);
        assert_eq!(masked.to_hex(), "dead0000");
        assert_eq!(masked.unknown_count(), 0);

        // an unknown in an *enabled* byte survives
        let mask_all = Value::ones(32);
        assert_eq!(data.mask_with(&mask_all).unknown_count(), 8);
    }

    #[test]
    fn slice_and_add() {
        let v = Value::parse_hex("0x0123456789abcdef", 64).unwrap();
        assert_eq!(v.slice(0, 32).to_hex(), "89abcdef");
        assert_eq!(v.slice(32, 32).to_hex(), "01234567");
        assert_eq!(Value::parse_hex("0x1c0100fc", 32).unwrap().add_u64(4).to_hex(), "1c010100");
        assert_eq!(Value::parse_hex("0xffffffff", 32).unwrap().add_u64(1).to_hex(), "00000000");
    }

    #[test]
    fn hex_grouping_aligns_from_the_least_significant_end() {
        assert_eq!(Value::parse_hex("0xdeadbeef", 32).unwrap().to_hex_grouped(4), "dead_beef");
        assert_eq!(Value::parse_hex("0xfff", 12).unwrap().to_hex_grouped(4), "fff");
        assert_eq!(Value::parse_hex("0x1deadbeef", 36).unwrap().to_hex_grouped(4), "1_dead_beef");
    }

    #[test]
    fn nibble_diff_is_msb_first_and_width_tolerant() {
        let a = Value::parse_hex("0xdeadbeef", 32).unwrap();
        let b = Value::parse_hex("0xdeadb0ef", 32).unwrap();
        let d = a.diff_nibbles_msb_first(&b);
        assert_eq!(d, vec![false, false, false, false, false, true, false, false]);
        assert!(a.diff_nibbles_msb_first(&a).iter().all(|x| !x));
    }

    #[test]
    fn differs_only_by_unknown() {
        let a = Value::parse_hex("0xdeadbeef", 32).unwrap();
        let b = Value::parse_hex("0xdeadbeex", 32).unwrap();
        let c = Value::parse_hex("0xdeadb0ef", 32).unwrap();
        assert!(a.differs_only_by_unknown(&b));
        assert!(!a.differs_only_by_unknown(&c));
        assert!(!a.differs_only_by_unknown(&a));
    }
}
