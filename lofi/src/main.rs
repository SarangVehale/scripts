//! lofi v3
//!
//! Keyboard:
//!   space    play/pause        n    next        p    prev
//!   ← →      seek ±10s        + -  volume      ↑ ↓  volume
//!   s        shuffle           r    repeat       f    search
//!   d        debug overlay     q    quit

use std::io::{self, Read, Write};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

mod app;
mod downloader;
mod player;
mod ui;
mod utils;

use app::config::load_tracks;
use app::state::{AppState, UiLayout};
use app::track::TrackStatus;
use downloader::yt_dlp::Downloader;
use player::ipc::MpvIpc;
use player::mpv::MpvPlayer;
use ui::render::terminal_size;

const TICK:             Duration = Duration::from_millis(250);
const IPC_WARMUP:       Duration = Duration::from_millis(1500);
const MAX_IPC_FAILURES: u32      = 12;
const VOL_STEP:         u8       = 5;

fn main() {
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore_terminal();
        default_hook(info);
    }));

    let layout = choose_layout();

    let tracks = load_tracks(
        concat!(env!("CARGO_MANIFEST_DIR"), "/config/tracks.toml"),
    ).expect("Failed to load config/tracks.toml");

    if tracks.is_empty() {
        eprintln!("No tracks in config/tracks.toml.");
        return;
    }

    let state      = Arc::new(Mutex::new(AppState::new(tracks, layout)));
    let mut dl     = Downloader::new();
    let mut player = MpvPlayer::new();

    let input_state = Arc::clone(&state);
    thread::spawn(move || input_loop(input_state));

    print!("\x1B[2J\x1B[?25l\x1B[H");
    io::stdout().flush().ok();

    let mut current_idx       = usize::MAX;
    let mut ipc_failures      = 0u32;
    let mut playback_started  = false;
    let mut switched_to_local = false;
    let mut last_tick         = Instant::now();
    let (mut last_tw, mut last_th) = terminal_size();

    loop {
        if !state.lock().unwrap().is_running { break; }

        let (tw, th) = terminal_size();
        if tw != last_tw || th != last_th {
            last_tw = tw; last_th = th;
            print!("\x1B[2J");
            io::stdout().flush().ok();
        }

        let idx = state.lock().unwrap().current_idx;
        if idx != current_idx {
            current_idx       = idx;
            ipc_failures      = 0;
            playback_started  = false;
            switched_to_local = false;

            let (url, resume_pos, local_path) = {
                let st = state.lock().unwrap();
                let t  = &st.tracks[idx];
                (t.url.clone(), t.resume_pos, t.local_path.clone())
            };

            let source = local_path.clone().unwrap_or_else(|| url.clone());
            if local_path.is_some() { switched_to_local = true; }

            let ok = match resume_pos {
                Some(p) if p > 1.0 => player.play_from(&source, p),
                _                  => player.play(&source),
            };

            if !ok {
                let mut st = state.lock().unwrap();
                st.tracks[idx].status = TrackStatus::Failed;
                st.status_msg = "mpv failed to start \u{2014} skipping".into();
                st.log("mpv spawn failed");
                st.advance_track();
            } else {
                let vol = state.lock().unwrap().volume;
                state.lock().unwrap().tracks[idx].play_count += 1;
                thread::sleep(IPC_WARMUP);
                MpvIpc::set_volume(vol);
            }
        }

        let time_pos = MpvIpc::get_time_pos();
        let duration = MpvIpc::get_duration();
        let buffered = MpvIpc::get_demuxer_cache_duration();

        if time_pos.is_some() { ipc_failures = 0; playback_started = true; }
        else if playback_started { ipc_failures += 1; }

        {
            let mut st = state.lock().unwrap();
            st.time_pos = time_pos;
            st.duration = duration;
            st.buffered = buffered;
            if let Some(t) = time_pos {
                if t > 0.5 { let i = st.current_idx; st.tracks[i].resume_pos = Some(t); }
            }
        }

        if !switched_to_local {
            let (is_ready, local_path, resume) = {
                let st = state.lock().unwrap();
                let tr = &st.tracks[current_idx];
                (tr.status == TrackStatus::Ready, tr.local_path.clone(), tr.resume_pos)
            };
            if is_ready {
                if let Some(local) = local_path {
                    switched_to_local = true;
                    player.stop();
                    let vol = state.lock().unwrap().volume;
                    match resume {
                        Some(p) if p > 1.0 => { player.play_from(&local, p); }
                        _                  => { player.play(&local); }
                    }
                    ipc_failures = 0; playback_started = false;
                    state.lock().unwrap().log(format!("Switched to local: {}", local));
                    thread::sleep(IPC_WARMUP);
                    MpvIpc::set_volume(vol);
                }
            }
        }

        let mpv_dead = ipc_failures >= MAX_IPC_FAILURES
            || (!playback_started && !player.is_alive());
        if mpv_dead {
            ipc_failures = 0; playback_started = false;
            let advanced = state.lock().unwrap().advance_track();
            if !advanced {
                let mut st = state.lock().unwrap();
                st.status_msg = "\u{266A} End of playlist \u{2014} press q to quit".into();
                st.is_playing = false;
                st.time_pos   = None;
            }
        }

        dl.tick(&state);

        state.lock().unwrap().tick += 1;
        ui::render::render(&*state.lock().unwrap());

        let elapsed = last_tick.elapsed();
        if elapsed < TICK { thread::sleep(TICK - elapsed); }
        last_tick = Instant::now();
    }

    player.stop();
    restore_terminal();
    println!("Goodbye \u{1F431}");
}

fn input_loop(state: Arc<Mutex<AppState>>) {
    set_raw_mode(true);
    let stdin      = io::stdin();
    let mut handle = stdin.lock();
    let mut buf    = [0u8; 64];

    loop {
        let n = match handle.read(&mut buf) {
            Ok(n) if n > 0 => n,
            _              => break,
        };
        let input = &buf[..n];

        // Escape sequences (arrows)
        if n >= 3 && input[0] == 0x1B && input[1] == b'[' {
            let search_open = state.lock().unwrap().search.open;
            match input[2] {
                b'A' => {
                    if search_open {
                        let mut st = state.lock().unwrap();
                        if st.search.cursor > 0 { st.search.cursor -= 1; }
                    } else {
                        let mut st = state.lock().unwrap();
                        st.volume = st.volume.saturating_add(VOL_STEP).min(100);
                        let v = st.volume; drop(st);
                        MpvIpc::set_volume(v);
                    }
                }
                b'B' => {
                    if search_open {
                        let mut st = state.lock().unwrap();
                        let max = st.search.results.len().saturating_sub(1);
                        if st.search.cursor < max { st.search.cursor += 1; }
                    } else {
                        let mut st = state.lock().unwrap();
                        st.volume = st.volume.saturating_sub(VOL_STEP);
                        let v = st.volume; drop(st);
                        MpvIpc::set_volume(v);
                    }
                }
                b'C' => { if !state.lock().unwrap().search.open { MpvIpc::seek_relative(10.0); } }
                b'D' => { if !state.lock().unwrap().search.open { MpvIpc::seek_relative(-10.0); } }
                _ => {}
            }
            continue;
        }

        // ESC alone — close search
        if n == 1 && input[0] == 0x1B {
            let mut st = state.lock().unwrap();
            if st.search.open {
                st.search.open = false;
                st.search.query.clear();
                st.search.results.clear();
            }
            continue;
        }

        let search_open = state.lock().unwrap().search.open;

        if search_open {
            match input[0] {
                0x0D | b'\n' => {
                    let mut st = state.lock().unwrap();
                    if let Some(&track_idx) = st.search.results.get(st.search.cursor) {
                        st.jump_to(track_idx);
                        st.search.open = false;
                        st.search.query.clear();
                        st.search.results.clear();
                        drop(st);
                        MpvIpc::quit();
                    }
                }
                0x7F | 0x08 => {
                    let mut st = state.lock().unwrap();
                    st.search.query.pop();
                    let tracks = st.tracks.clone();
                    st.search.filter(&tracks);
                }
                0x03 => {
                    state.lock().unwrap().is_running = false;
                    MpvIpc::quit();
                    break;
                }
                b if b >= 0x20 && b < 0x7F => {
                    let mut st = state.lock().unwrap();
                    st.search.query.push(input[0] as char);
                    let tracks = st.tracks.clone();
                    st.search.filter(&tracks);
                }
                _ => {}
            }
            continue;
        }

        let mut st = state.lock().unwrap();
        match input[0] {
            b'q' | 0x03 => {
                st.is_running = false;
                MpvIpc::quit();
                break;
            }
            b' ' => {
                st.is_playing = !st.is_playing;
                if st.is_playing { MpvIpc::resume(); } else { MpvIpc::pause(); }
            }
            b'n' => { save_pos(&mut st); MpvIpc::quit(); st.advance_track(); }
            b'p' => { save_pos(&mut st); MpvIpc::quit(); st.prev_track(); }
            b's' => { st.shuffle = !st.shuffle; st.rebuild_order(); }
            b'r' => { st.repeat = st.repeat.next(); }
            b'+' | b'=' => {
                st.volume = st.volume.saturating_add(VOL_STEP).min(100);
                let v = st.volume; drop(st); MpvIpc::set_volume(v); continue;
            }
            b'-' => {
                st.volume = st.volume.saturating_sub(VOL_STEP);
                let v = st.volume; drop(st); MpvIpc::set_volume(v); continue;
            }
            b'f' => {
                st.search.open = !st.search.open;
                if st.search.open {
                    st.search.query.clear();
                    st.search.cursor = 0;
                    let tracks = st.tracks.clone();
                    st.search.filter(&tracks);
                }
            }
            b'd' => { st.debug = !st.debug; }
            _ => {}
        }
    }

    set_raw_mode(false);
}

fn save_pos(st: &mut AppState) {
    if let Some(t) = st.time_pos {
        let i = st.current_idx;
        st.tracks[i].resume_pos = Some(t);
    }
}

fn set_raw_mode(enable: bool) {
    if enable {
        let _ = std::process::Command::new("stty").args(["raw", "-echo"]).status();
    } else {
        let _ = std::process::Command::new("stty").arg("sane").status();
    }
}

fn restore_terminal() {
    print!("\x1B[?25h\x1B[2J\x1B[H");
    let _ = io::stdout().flush();
    set_raw_mode(false);
}

fn choose_layout() -> UiLayout {
    println!("\x1B[38;2;203;166;247m\u{256D}{}\u{256E}\x1B[0m", "\u{2500}".repeat(46));
    println!("\x1B[38;2;108;112;134m\u{2502}\x1B[0m\x1B[38;2;186;194;222m         lofi \u{2014} choose your layout          \x1B[0m\x1B[38;2;108;112;134m\u{2502}\x1B[0m");
    println!("\x1B[38;2;108;112;134m\u{2502}\x1B[0m                                               \x1B[38;2;108;112;134m\u{2502}\x1B[0m");
    println!("\x1B[38;2;108;112;134m\u{2502}\x1B[0m  \x1B[38;2;148;226;213m1  Classic\x1B[0m  cat centred, spacious              \x1B[38;2;108;112;134m\u{2502}\x1B[0m");
    println!("\x1B[38;2;108;112;134m\u{2502}\x1B[0m  \x1B[38;2;148;226;213m2  Compact\x1B[0m  cat in corner, denser              \x1B[38;2;108;112;134m\u{2502}\x1B[0m");
    println!("\x1B[38;2;108;112;134m\u{2502}\x1B[0m                                               \x1B[38;2;108;112;134m\u{2502}\x1B[0m");
    println!("\x1B[38;2;203;166;247m\u{2570}{}\u{256F}\x1B[0m", "\u{2500}".repeat(46));
    print!("  Enter 1 or 2 [default: 1]: ");
    io::stdout().flush().ok();
    let mut line = String::new();
    io::stdin().read_line(&mut line).ok();
    match line.trim() { "2" => UiLayout::Compact, _ => UiLayout::Classic }
}
