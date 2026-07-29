// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Comparison of HCI-Core and HWPE-Stream transaction logs.
//!
//! The logs are produced in simulation by the `hci_transaction_tracer` and
//! `hwpe_stream_transaction_tracer` SystemVerilog modules, and follow the JSON
//! schemas in `tracer/` (HCI) and `hwpe-stream/tracer/` (HWPE-Stream).
//!
//! The guiding rule of the whole crate is that only the *content* of valid data
//! -- transactions whose handshake was satisfied -- is compared. The cycle at
//! which a transaction happened is carried through the pipeline and reported, so
//! a difference can be found in a waveform, but it never takes part in a
//! comparison; see [`model::Beat`] and [`compare::key_of`].

#![forbid(unsafe_code)]

pub mod cli;
pub mod color;
pub mod compare;
pub mod diff;
pub mod error;
pub mod load;
pub mod model;
pub mod repair;
pub mod report;
pub mod run;
pub mod schema;
pub mod split;
pub mod value;

pub use error::{Error, Result};
