// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Error type shared by the whole crate.
//!
//! Hand-rolled rather than pulled from `thiserror`/`anyhow`, so that the crate
//! depends only on `serde`, `serde_json`, `clap` and `owo-colors`.

use std::fmt;
use std::path::{Path, PathBuf};

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    /// The log file could not be read.
    Io { path: PathBuf, source: std::io::Error },
    /// The log file is not valid JSON, or does not match the schema.
    Json { path: PathBuf, source: serde_json::Error },
    /// The log file was cut short and could not be repaired.
    Truncated { path: PathBuf, detail: String },
    /// The log file is valid JSON but semantically inconsistent.
    Schema { path: PathBuf, msg: String },
    /// A hexadecimal field could not be interpreted.
    Field { path: PathBuf, seq: Option<u64>, field: String, msg: String },
    /// Two logs cannot be compared as they stand.
    Width(String),
    /// `--x-policy=error` and an unknown bit was found in an enabled byte.
    UnknownBits { path: PathBuf, seq: u64, field: String },
    /// Bad combination of command-line options.
    Usage(String),
}

impl Error {
    /// Every error maps to exit code 2; the caller owns exit codes 0/1/4.
    pub fn exit_code(&self) -> i32 {
        2
    }

    pub fn io(path: &Path, source: std::io::Error) -> Error {
        Error::Io { path: path.to_path_buf(), source }
    }

    pub fn schema(path: &Path, msg: impl Into<String>) -> Error {
        Error::Schema { path: path.to_path_buf(), msg: msg.into() }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io { path, source } => write!(f, "cannot read {}: {source}", path.display()),
            Error::Json { path, source } => {
                write!(f, "{} is not a valid transaction log: {source}", path.display())
            }
            Error::Truncated { path, detail } => write!(
                f,
                "{} was cut short and could not be repaired: {detail}",
                path.display()
            ),
            Error::Schema { path, msg } => write!(f, "{}: {msg}", path.display()),
            Error::Field { path, seq, field, msg } => match seq {
                Some(seq) => {
                    write!(f, "{}: transaction seq={seq}, field `{field}`: {msg}", path.display())
                }
                None => write!(f, "{}: field `{field}`: {msg}", path.display()),
            },
            Error::Width(msg) => write!(f, "{msg}"),
            Error::UnknownBits { path, seq, field } => write!(
                f,
                "{}: transaction seq={seq} has x/z bits in the enabled part of `{field}` \
                 (--x-policy=error)",
                path.display()
            ),
            Error::Usage(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Io { source, .. } => Some(source),
            Error::Json { source, .. } => Some(source),
            _ => None,
        }
    }
}
