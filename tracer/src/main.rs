// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! `hci-tracer`: compare HCI-Core and HWPE-Stream transaction logs.

use std::io::{self, IsTerminal, Write};
use std::process::ExitCode;

use clap::Parser;

use hci_tracer::cli::Cli;
use hci_tracer::run::run;

fn main() -> ExitCode {
    let cli = Cli::parse();
    let stdout = io::stdout();
    let is_tty = stdout.is_terminal();
    let mut out = io::BufWriter::new(stdout.lock());

    let code = match run(&cli, &mut out, is_tty) {
        Ok(code) => code,
        Err(e) => {
            let _ = out.flush();
            eprintln!("hci-tracer: error: {e}");
            e.exit_code()
        }
    };

    match out.flush() {
        Ok(()) => {}
        // `| head` and friends: nothing left to say.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => return ExitCode::from(0),
        Err(e) => {
            eprintln!("hci-tracer: error: cannot write to stdout: {e}");
            return ExitCode::from(2);
        }
    }
    ExitCode::from(code as u8)
}
