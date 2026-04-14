//! Terminal UI — Catppuccin Mocha, two layouts, no mouse.
//!
//! The bottom "wave" row shows per-track cache state as animated block chars:
//!   cached      → tall steady ▇ (dim), current track ripples green
//!   downloading → animated sine wave in yellow
//!   queued      → flat ▁ in dim
//!   failed      → · in red

extern crate libc;
use std::io::{self, Write};
use unicode_width::UnicodeWidthStr;
use crate::app::state::{AppState, UiLayout};
use crate::app::track::TrackStatus;

const MAUVE:    &str = "\x1B[38;2;203;166;247m";
const TEAL:     &str = "\x1B[38;2;148;226;213m";
const GREEN:    &str = "\x1B[38;2;166;227;161m";
const YELLOW:   &str = "\x1B[38;2;249;226;175m";
const RED:      &str = "\x1B[38;2;243;139;168m";
const SUBTEXT1: &str = "\x1B[38;2;186;194;222m";
const SUBTEXT0: &str = "\x1B[38;2;166;173;200m";
const OVERLAY2: &str = "\x1B[38;2;147;153;178m";
const OVERLAY1: &str = "\x1B[38;2;127;132;156m";
const OVERLAY0: &str = "\x1B[38;2;108;112;134m";
const SURFACE2: &str = "\x1B[38;2;88;91;112m";
const SURFACE0: &str = "\x1B[38;2;49;50;68m";
const RESET:    &str = "\x1B[0m";

const INNER_C:  usize = 58;
const HEIGHT_C: usize = 14;
const BAR_W_C:  usize = 32;
const INNER_K:  usize = 56;
const HEIGHT_K: usize = 10;
const BAR_W_K:  usize = 18;
const CAT_COLS: usize = 10;

const CAT_PLAYING: &[(&str, &str, &str)] = &[
    ("/\\_/\\", "( ^.^ )", "> \u{266A} <"),
    ("/\\_/\\", "( -.^ )", "~ \u{266A} <"),
    ("/\\_/\\", "( ^.^ )", "> \u{266A} ~"),
    ("/\\_/\\", "( ^.- )", "> \u{266A} <"),
];
const CAT_PAUSED: &[(&str, &str, &str)] = &[
    ("/\\_/\\", "( o.o )", "> ^ <"),
    ("/\\_/\\", "( -.- )", "> ^ <"),
];

fn cat_frame(state: &AppState) -> (&'static str, &'static str, &'static str) {
    if state.is_playing && state.time_pos.is_some() {
        CAT_PLAYING[(state.tick / 3) as usize % CAT_PLAYING.len()]
    } else {
        CAT_PAUSED[(state.tick / 10) as usize % CAT_PAUSED.len()]
    }
}

const SPINNER: &[char] = &['\u{280B}', '\u{2819}', '\u{2838}', '\u{2834}', '\u{2826}', '\u{2807}'];
fn spinner(tick: u64) -> char { SPINNER[(tick / 2) as usize % SPINNER.len()] }

const BLOCKS: &[char] = &['\u{2581}', '\u{2582}', '\u{2583}', '\u{2584}', '\u{2585}', '\u{2586}', '\u{2587}', '\u{2588}'];

fn wave_char(status: &TrackStatus, track_idx: usize, tick: u64, is_current: bool) -> (char, &'static str) {
    match status {
        TrackStatus::Ready => {
            if is_current {
                let phase = (tick as f64 * 0.4 + track_idx as f64).sin();
                let h = ((phase * 1.5 + 6.5) as usize).clamp(4, 7);
                (BLOCKS[h], GREEN)
            } else {
                (BLOCKS[6], SURFACE2)
            }
        }
        TrackStatus::Downloading => {
            let phase = (tick as f64 * 0.6 + track_idx as f64 * 1.2).sin();
            let h = ((phase * 3.0 + 3.5) as usize).clamp(0, 7);
            (BLOCKS[h], YELLOW)
        }
        TrackStatus::NotDownloaded => ('\u{2581}', OVERLAY0),
        TrackStatus::Failed        => ('\u{00B7}', RED),
    }
}

struct Canvas { row: usize, col: usize }
impl Canvas {
    fn new(top: usize, left: usize) -> Self { Self { row: top + 1, col: left + 1 } }
    fn emit(&mut self, s: &str) -> usize {
        let r = self.row;
        print!("\x1B[{};{}H{}\x1B[K", r, self.col, s);
        self.row += 1; r
    }
}

pub fn render(state: &AppState) {
    let (tw, th) = terminal_size();
    match state.layout {
        UiLayout::Classic => render_classic(state, tw, th),
        UiLayout::Compact => render_compact(state, tw, th),
    }
    if state.search.open { render_search(state, tw, th); }
    if state.debug       { render_debug(state, tw, th); }
    io::stdout().flush().ok();
}

pub fn terminal_size() -> (usize, usize) {
    #[cfg(unix)]
    unsafe {
        let mut ws: libc::winsize = std::mem::zeroed();
        if libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut ws) == 0
            && ws.ws_col > 0 && ws.ws_row > 0
        { return (ws.ws_col as usize, ws.ws_row as usize); }
    }
    (80, 24)
}

fn render_classic(state: &AppState, tw: usize, th: usize) {
    let inner = INNER_C; let bar_w = BAR_W_C;
    let left  = tw.saturating_sub(inner + 2) / 2;
    let top   = th.saturating_sub(HEIGHT_C) / 2;
    let mut cv = Canvas::new(top, left);

    let title        = track_title(state);
    let (ca, cb, cc) = cat_frame(state);
    let ctrl         = ctrl_line(state, inner);
    let pline        = progress_line(state, inner, bar_w);
    let wave         = wave_line(state, inner);

    cv.emit(&border_top(inner));
    cv.emit(&brow(blank(inner)));
    cv.emit(&brow_c(centre(&format!("\u{266A}  {}  \u{266A}", title), inner), MAUVE));
    cv.emit(&brow(blank(inner)));
    cv.emit(&brow_c(centre(ca, inner), TEAL));
    cv.emit(&brow_c(centre(cb, inner), TEAL));
    cv.emit(&brow_c(centre(cc, inner), TEAL));
    cv.emit(&brow(blank(inner)));
    cv.emit(&brow_raw(&pline));
    cv.emit(&brow(blank(inner)));
    cv.emit(&brow_raw(&ctrl));
    cv.emit(&border_mid(inner));
    cv.emit(&brow_raw(&wave));
    cv.emit(&border_bot(inner));

    for extra in 0..4 { print!("\x1B[{};1H\x1B[2K", top + HEIGHT_C + 1 + extra); }
}

fn render_compact(state: &AppState, tw: usize, th: usize) {
    let inner  = INNER_K; let bar_w = BAR_W_K;
    let left   = tw.saturating_sub(inner + 2) / 2;
    let top    = th.saturating_sub(HEIGHT_K) / 2;
    let left_w = inner - CAT_COLS;
    let mut cv = Canvas::new(top, left);

    let title        = track_title(state);
    let (ca, cb, cc) = cat_frame(state);
    let ctrl         = ctrl_line(state, inner);
    let wave         = wave_line(state, inner);

    let title_left = lpad(&format!("  \u{266A}  {}", fit(&title, left_w.saturating_sub(7))), left_w);
    let cat1_right = format!("{}{:<10}{}", TEAL, ca, RESET);
    let blank_left = " ".repeat(left_w);
    let cat2_right = format!("{}{:<10}{}", TEAL, cb, RESET);
    let prog_left  = progress_left(state, bar_w, left_w);
    let cat3_right = format!("{}{:<10}{}", TEAL, cc, RESET);

    cv.emit(&border_top(inner));
    cv.emit(&brow(blank(inner)));
    cv.emit(&brow_raw(&format!("{}{}{}\x1B[0m", OVERLAY2, title_left, cat1_right)));
    cv.emit(&brow_raw(&format!("{}{}{}\x1B[0m", OVERLAY2, blank_left, cat2_right)));
    cv.emit(&brow_raw(&format!("{}{}{}\x1B[0m", OVERLAY2, prog_left,  cat3_right)));
    cv.emit(&brow(blank(inner)));
    cv.emit(&brow_raw(&ctrl));
    cv.emit(&border_mid(inner));
    cv.emit(&brow_raw(&wave));
    cv.emit(&border_bot(inner));

    for extra in 0..6 { print!("\x1B[{};1H\x1B[2K", top + HEIGHT_K + 1 + extra); }
}

fn render_search(state: &AppState, tw: usize, th: usize) {
    let w         = (tw.min(52)).max(30);
    let left      = (tw.saturating_sub(w)) / 2 + 1;
    let max_res   = 6usize;
    let top       = (th.saturating_sub(max_res + 6)) / 2 + 1;
    let inner     = w - 2;

    print!("\x1B[{};{}H{}\u{256D} search {}\u{256E}{}",
        top, left, MAUVE, "\u{2500}".repeat(inner.saturating_sub(8)), RESET);

    let q_display = fit(&state.search.query, inner - 4);
    let q_pad     = " ".repeat(inner.saturating_sub(4 + disp(&q_display)));
    print!("\x1B[{};{}H{}│{} {}\u{258C}{}{} │{}{}",
        top + 1, left, OVERLAY0,
        SUBTEXT1, q_display, MAUVE, q_pad,
        OVERLAY0, RESET);
    
    print!("\x1B[{};{}H{}\u{251C}{}\u{2524}{}",
        top + 2, left, OVERLAY0, "\u{2500}".repeat(inner), RESET);

    for i in 0..max_res {
        let row = top + 3 + i;
        if i < state.search.results.len() {
            let track_idx = state.search.results[i];
            let t         = &state.tracks[track_idx];
            let selected  = i == state.search.cursor;
            let prefix    = if selected { format!("{}\u{25B6} ", MAUVE) } else { format!("{}  ", OVERLAY1) };
            let name      = fit(&t.title, inner - 4);
            let name_w    = disp(&t.title).min(inner - 4);
            let pad       = " ".repeat(inner.saturating_sub(4 + name_w));
            let bg        = if selected { "\x1B[48;2;49;50;68m" } else { "" };
            print!("\x1B[{};{}H{}{}│{}{}{}{}{}{}│{}",
                row, left, OVERLAY0, bg, prefix, SUBTEXT1, name, pad, RESET, OVERLAY0, RESET);
        } else {
            print!("\x1B[{};{}H{}│{}│{}",
                row, left, OVERLAY0, " ".repeat(inner), RESET);
        }
    }

    print!("\x1B[{};{}H{}\u{2570}{}\u{256F}{}",
        top + 3 + max_res, left, MAUVE, "\u{2500}".repeat(inner), RESET);
    print!("\x1B[{};{}H{}  \u{2191}\u{2193} navigate   enter play   esc close{}",
        top + 4 + max_res, left, OVERLAY0, RESET);
}

fn render_debug(state: &AppState, tw: usize, th: usize) {
    let lines   = state.debug_log.iter().rev().take(8).collect::<Vec<_>>();
    let w       = tw.min(70);
    let left    = tw.saturating_sub(w) / 2;
    let top_row = th.saturating_sub(lines.len() + 2);
    print!("\x1B[{};{}H{}\u{256D}\u{2500} debug {}\u{2510}{}",
    top_row, left + 1, SURFACE2, "─".repeat(w - 10), RESET);
    // print!("\x1B[{};{}H{}\u{250C}\u{2500} debug {}{}\u{2510}{}",
        // top_row, left + 1, SURFACE2, "\u{2500}".repeat(w.saturating_sub(10)), RESET, SURFACE2, RESET);
    for (i, line) in lines.iter().enumerate() {
        print!("\x1B[{};{}H{}│ {}{}{} │{}",
            top_row + 1 + i, left + 1, SURFACE2, OVERLAY1, fit(line, w - 4), SURFACE2, RESET);
    }
    print!("\x1B[{};{}H{}\u{2514}{}\u{2518}{}",
        top_row + 1 + lines.len(), left + 1, SURFACE2, "\u{2500}".repeat(w - 2), RESET);
}

fn border_top(inner: usize) -> String { format!("{}\u{256D}{}\u{256E}{}", OVERLAY0, "\u{2500}".repeat(inner), RESET) }
fn border_mid(inner: usize) -> String { format!("{}\u{251C}{}\u{2524}{}", OVERLAY0, "\u{2500}".repeat(inner), RESET) }
fn border_bot(inner: usize) -> String { format!("{}\u{2570}{}\u{256F}{}", OVERLAY0, "\u{2500}".repeat(inner), RESET) }

fn brow(content: String) -> String {
    format!("{}│{}{}{}│{}", OVERLAY0, OVERLAY2, content, OVERLAY0, RESET)
}
fn brow_c(content: String, color: &str) -> String {
    format!("{}│{}{}{}{}│{}", OVERLAY0, color, content, RESET, OVERLAY0, RESET)
}
fn brow_raw(content: &str) -> String {
    format!("{}│{}{}│{}", OVERLAY0, content, OVERLAY0, RESET)
}

fn progress_line(state: &AppState, inner: usize, bar_w: usize) -> String {
    match (state.time_pos, state.duration) {
        (Some(t), Some(d)) if d > 0.0 => {
            let played  = ((t / d).clamp(0.0, 1.0) * bar_w as f64).round() as usize;
            let buf_end = state.buffered.map(|b| ((t + b) / d).clamp(0.0, 1.0)).unwrap_or(t / d);
            let bufd    = ((buf_end * bar_w as f64).round() as usize).clamp(played, bar_w);
            let bar     = format!("{}{}{}{}{}{}\x1B[0m",
                MAUVE,    "\u{2588}".repeat(played),
                SURFACE2, "\u{2593}".repeat(bufd.saturating_sub(played)),
                SURFACE0, "\u{2591}".repeat(bar_w.saturating_sub(bufd)));
            let time    = format!("  {} / {}", fmt_time(t), fmt_time(d));
            let pad     = " ".repeat(inner.saturating_sub(2 + bar_w + disp(&time)));
            format!("{}{}{}{}{}{}{}",  OVERLAY2, "  ", bar, SUBTEXT0, time, pad, RESET)
        }
        _ => {
            let msg = if state.time_pos.is_none() {
                format!("{} connecting...", spinner(state.tick))
            } else {
                format!("{} buffering...", spinner(state.tick))
            };
            let pad = " ".repeat(inner.saturating_sub(2 + disp(&msg)));
            format!("{}  {}{}{}", OVERLAY1, msg, pad, RESET)
        }
    }
}

fn progress_left(state: &AppState, bar_w: usize, left_w: usize) -> String {
    match (state.time_pos, state.duration) {
        (Some(t), Some(d)) if d > 0.0 => {
            let played  = ((t / d).clamp(0.0, 1.0) * bar_w as f64).round() as usize;
            let buf_end = state.buffered.map(|b| ((t + b) / d).clamp(0.0, 1.0)).unwrap_or(t / d);
            let bufd    = ((buf_end * bar_w as f64).round() as usize).clamp(played, bar_w);
            let bar     = format!("{}{}{}{}{}{}\x1B[0m",
                MAUVE, "\u{2588}".repeat(played),
                SURFACE2, "\u{2593}".repeat(bufd.saturating_sub(played)),
                SURFACE0, "\u{2591}".repeat(bar_w.saturating_sub(bufd)));
            let time    = format!("  {} / {}", fmt_time(t), fmt_time(d));
            let pad     = " ".repeat(left_w.saturating_sub(2 + bar_w + disp(&time)));
            format!("{}{}{}{}{}{}",  OVERLAY2, "  ", bar, SUBTEXT0, time, pad)
        }
        _ => {
            let msg = format!("{} connecting...", spinner(state.tick));
            format!("{}  {}{}", OVERLAY1, msg, " ".repeat(left_w.saturating_sub(2 + disp(&msg))))
        }
    }
}

fn ctrl_line(state: &AppState, inner: usize) -> String {
    let play_icon = if state.is_playing { "\u{23F8}" } else { "\u{25B6}" };
    let shuf_icon = if state.shuffle {
        format!("{}s{}", TEAL, RESET)
    } else {
        format!("{}s{}", SURFACE2, RESET)
    };
    let rep_icon = match state.repeat {
        crate::app::state::RepeatMode::None => format!("{}r{}", SURFACE2, RESET),
        crate::app::state::RepeatMode::All  => format!("{}r{}", TEAL, RESET),
        crate::app::state::RepeatMode::One  => format!("{}r\u{00B9}{}", MAUVE, RESET),
    };
    let left_part  = format!("{}\u{23EE}{} p  {}{}{} spc  {}\u{23ED}{} n  {}q{}",
        SUBTEXT1, RESET, SUBTEXT1, play_icon, RESET, SUBTEXT1, RESET, OVERLAY1, RESET);
    let right_part = format!("  {}f{}  {}  {}", OVERLAY1, RESET, shuf_icon, rep_icon);
    let lw  = disp_stripped(&left_part);
    let rw  = disp_stripped(&right_part);
    let gap = inner.saturating_sub(lw + rw + 4);
    format!("{}  {}{}{}{}  {}", OVERLAY2, left_part, " ".repeat(gap), right_part, " ".repeat(0), RESET)
}

fn wave_line(state: &AppState, inner: usize) -> String {
    let n = state.tracks.len();
    if n == 0 { return " ".repeat(inner); }

    let cell_w    = ((inner - 2) / n).max(4).min(9);
    let mut out   = String::from("  ");

    for (i, track) in state.tracks.iter().enumerate() {
        let is_cur    = i == state.current_idx;
        let wave_chars = (cell_w - 1).max(1);
        for w in 0..wave_chars {
            let t           = state.tick.wrapping_add(w as u64 * 2);
            let (ch, color) = wave_char(&track.status, i, t, is_cur);
            out.push_str(if is_cur { MAUVE } else { color });
            out.push(ch);
            out.push_str(RESET);
        }
        out.push(' ');
    }

    let used = cell_w * n + 2;
    if inner > used { out.push_str(&" ".repeat(inner - used)); }
    out
}

fn track_title(state: &AppState) -> String {
    state.current_track().map(|t| t.title.clone()).unwrap_or_else(|| "\u{2014}".into())
}
fn fmt_time(secs: f64) -> String {
    let s = secs as u64;
    if s >= 3600 { format!("{}:{:02}:{:02}", s/3600, (s%3600)/60, s%60) }
    else         { format!("{:02}:{:02}", s/60, s%60) }
}
fn blank(w: usize) -> String { " ".repeat(w) }
fn centre(text: &str, width: usize) -> String {
    let tw = disp(text);
    if tw >= width { return fit(text, width); }
    let pad = width - tw; let l = pad / 2;
    format!("{}{}{}", " ".repeat(l), text, " ".repeat(pad - l))
}
fn lpad(text: &str, width: usize) -> String {
    let tw = disp(text);
    if tw >= width { return fit(text, width); }
    format!("{}{}", text, " ".repeat(width - tw))
}
fn fit(text: &str, max_w: usize) -> String {
    let mut out = String::new(); let mut w = 0usize;
    for ch in text.chars() {
        let cw = unicode_width::UnicodeWidthChar::width(ch).unwrap_or(0);
        if w + cw > max_w { break; }
        out.push(ch); w += cw;
    }
    if w < max_w { out.push_str(&" ".repeat(max_w - w)); }
    out
}
fn disp(s: &str) -> usize { UnicodeWidthStr::width(s) }
fn disp_stripped(s: &str) -> usize {
    let mut w = 0usize; let mut esc = false;
    for ch in s.chars() {
        if ch == '\x1B' { esc = true; continue; }
        if esc { if ch == 'm' { esc = false; } continue; }
        w += unicode_width::UnicodeWidthChar::width(ch).unwrap_or(0);
    }
    w
}
