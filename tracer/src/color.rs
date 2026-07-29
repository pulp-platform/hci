// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see tracer/LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Francesco Conti <f.conti@unibo.it>

//! Colour policy and palette.
//!
//! Colours are resolved once, up front, and handed to the report as a
//! [`Palette`]; nothing downstream needs to know whether colour is on.

use owo_colors::{OwoColorize, Style};

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum ColorChoice {
    Auto,
    Always,
    Never,
}

/// Environment lookup, injectable so the policy can be unit-tested without
/// mutating the process environment.
pub trait EnvLike {
    fn var(&self, key: &str) -> Option<String>;
}

pub struct RealEnv;

impl EnvLike for RealEnv {
    fn var(&self, key: &str) -> Option<String> {
        std::env::var(key).ok()
    }
}

/// `Auto` turns colour on only for a terminal that has not asked for plain
/// output. `CLICOLOR_FORCE=1` forces it on even through a pipe; `Always`
/// deliberately overrides `NO_COLOR`.
pub fn use_color(choice: ColorChoice, out_is_tty: bool, env: &dyn EnvLike) -> bool {
    match choice {
        ColorChoice::Always => true,
        ColorChoice::Never => false,
        ColorChoice::Auto => {
            let no_color = env.var("NO_COLOR").is_some_and(|v| !v.is_empty());
            let dumb = env.var("TERM").as_deref() == Some("dumb");
            let forced = env.var("CLICOLOR_FORCE").is_some_and(|v| v != "0" && !v.is_empty());
            if no_color || dumb {
                false
            } else {
                out_is_tty || forced
            }
        }
    }
}

pub struct Palette {
    pub enabled: bool,
    bad: Style,
    good: Style,
    warn: Style,
    dim: Style,
    hdr: Style,
    meta: Style,
}

impl Palette {
    pub fn new(enabled: bool) -> Palette {
        Palette {
            enabled,
            bad: Style::new().red().bold(),
            good: Style::new().green(),
            warn: Style::new().yellow(),
            dim: Style::new().bright_black(),
            hdr: Style::new().bold(),
            meta: Style::new().cyan(),
        }
    }

    fn wrap(&self, style: Style, s: &str) -> String {
        if self.enabled {
            format!("{}", s.style(style))
        } else {
            s.to_string()
        }
    }

    /// A difference: the one thing that must jump out of the page.
    pub fn bad(&self, s: &str) -> String {
        self.wrap(self.bad, s)
    }

    pub fn good(&self, s: &str) -> String {
        self.wrap(self.good, s)
    }

    pub fn warn(&self, s: &str) -> String {
        self.wrap(self.warn, s)
    }

    pub fn dim(&self, s: &str) -> String {
        self.wrap(self.dim, s)
    }

    pub fn hdr(&self, s: &str) -> String {
        self.wrap(self.hdr, s)
    }

    pub fn meta(&self, s: &str) -> String {
        self.wrap(self.meta, s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeEnv(Vec<(&'static str, &'static str)>);

    impl EnvLike for FakeEnv {
        fn var(&self, key: &str) -> Option<String> {
            self.0.iter().find(|(k, _)| *k == key).map(|(_, v)| v.to_string())
        }
    }

    fn env(pairs: &[(&'static str, &'static str)]) -> FakeEnv {
        FakeEnv(pairs.to_vec())
    }

    #[test]
    fn auto_follows_the_terminal() {
        assert!(use_color(ColorChoice::Auto, true, &env(&[])));
        assert!(!use_color(ColorChoice::Auto, false, &env(&[])));
    }

    #[test]
    fn auto_honours_no_color_and_dumb_terminals() {
        assert!(!use_color(ColorChoice::Auto, true, &env(&[("NO_COLOR", "1")])));
        // An empty NO_COLOR is not a request for plain output.
        assert!(use_color(ColorChoice::Auto, true, &env(&[("NO_COLOR", "")])));
        assert!(!use_color(ColorChoice::Auto, true, &env(&[("TERM", "dumb")])));
    }

    #[test]
    fn clicolor_force_wins_over_a_pipe_but_not_over_no_color() {
        assert!(use_color(ColorChoice::Auto, false, &env(&[("CLICOLOR_FORCE", "1")])));
        assert!(!use_color(ColorChoice::Auto, false, &env(&[("CLICOLOR_FORCE", "0")])));
        assert!(!use_color(
            ColorChoice::Auto,
            false,
            &env(&[("CLICOLOR_FORCE", "1"), ("NO_COLOR", "1")])
        ));
    }

    #[test]
    fn explicit_choices_override_everything() {
        assert!(use_color(ColorChoice::Always, false, &env(&[("NO_COLOR", "1")])));
        assert!(!use_color(ColorChoice::Never, true, &env(&[("CLICOLOR_FORCE", "1")])));
    }

    #[test]
    fn a_disabled_palette_emits_no_escapes() {
        let p = Palette::new(false);
        assert_eq!(p.bad("beef"), "beef");
        let p = Palette::new(true);
        assert!(p.bad("beef").contains('\x1b'));
    }
}
