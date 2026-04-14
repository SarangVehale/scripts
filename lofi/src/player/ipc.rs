use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;
use crate::player::mpv::IPC_SOCKET;

pub struct MpvIpc;

impl MpvIpc {
    fn connect() -> Option<UnixStream> {
        let s = UnixStream::connect(IPC_SOCKET).ok()?;
        let _ = s.set_read_timeout(Some(Duration::from_millis(300)));
        Some(s)
    }

    pub fn send(cmd: &str) {
        if let Some(mut s) = Self::connect() {
            let _ = s.write_all(cmd.as_bytes());
            let _ = s.write_all(b"\n");
        }
    }

    fn request(cmd: &str) -> Option<String> {
        let mut s = Self::connect()?;
        let _ = s.write_all(cmd.as_bytes());
        let _ = s.write_all(b"\n");
        let mut r = BufReader::new(s);
        let mut line = String::new();
        let _ = r.read_line(&mut line);
        if line.is_empty() { None } else { Some(line) }
    }

    fn get_prop(p: &str) -> Option<String> {
        Self::request(&format!(r#"{{"command":["get_property","{}"]}}"#, p))
    }

    pub fn get_time_pos()               -> Option<f64> { parse_f64(&Self::get_prop("time-pos")?) }
    pub fn get_duration()               -> Option<f64> { parse_f64(&Self::get_prop("duration")?) }
    pub fn get_demuxer_cache_duration() -> Option<f64> { parse_f64(&Self::get_prop("demuxer-cache-duration")?) }

    pub fn pause()  { Self::send(r#"{"command":["set_property","pause",true]}"#);  }
    pub fn resume() { Self::send(r#"{"command":["set_property","pause",false]}"#); }
    pub fn quit()   { Self::send(r#"{"command":["quit"]}"#); }

    pub fn seek(pos: f64) {
        Self::send(&format!(r#"{{"command":["seek",{},"absolute"]}}"#, pos));
    }
    pub fn seek_relative(delta: f64) {
        Self::send(&format!(r#"{{"command":["seek",{},"relative"]}}"#, delta));
    }
    pub fn set_volume(vol: u8) {
        Self::send(&format!(r#"{{"command":["set_property","volume",{}]}}"#, vol));
    }
}

fn parse_f64(json: &str) -> Option<f64> {
    let key   = "\"data\":";
    let start = json.find(key)? + key.len();
    let slice = json[start..].trim_start();
    if slice.starts_with("null") || slice.starts_with('"') || slice.starts_with('{') {
        return None;
    }
    let num: String = slice.chars()
        .take_while(|c| c.is_ascii_digit() || matches!(c, '.' | '-' | 'e' | 'E' | '+'))
        .collect();
    num.parse().ok()
}
