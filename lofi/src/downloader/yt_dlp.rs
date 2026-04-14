use std::fs;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::app::state::AppState;
use crate::app::track::TrackStatus;
use crate::utils::hash::url_hash;

pub const CACHE_DIR:   &str = "/tmp/lofi-cache";
const MAX_PARALLEL:    usize = 2;
const RATE_LIMIT:      &str  = "500K";
const MAX_RETRIES:     u8    = 3;
const RETRY_BACKOFF:   u64   = 20;
const MAX_CACHE_BYTES: u64   = 500 * 1024 * 1024;

pub struct Downloader {
    active:      Vec<ActiveJob>,
    retry_queue: Vec<RetryEntry>,
}

struct ActiveJob   { track_idx: usize, output_path: PathBuf, child: Child }
struct RetryEntry  { track_idx: usize, retry_at: u64 }

impl Downloader {
    pub fn new() -> Self {
        fs::create_dir_all(CACHE_DIR).ok();
        Self { active: Vec::new(), retry_queue: Vec::new() }
    }

    pub fn tick(&mut self, state: &Arc<Mutex<AppState>>) {
        let tick = state.lock().unwrap().tick;

        // Reap finished downloads.
        let mut i = 0;
        while i < self.active.len() {
            match self.active[i].child.try_wait() {
                Ok(Some(status)) => {
                    let job   = self.active.remove(i);
                    let mut st = state.lock().unwrap();
                    let track  = &mut st.tracks[job.track_idx];
                    if status.success() && job.output_path.exists() {
                        track.local_path  = Some(job.output_path.to_string_lossy().into_owned());
                        track.status      = TrackStatus::Ready;
                        track.retry_count = 0;
                        let title = st.tracks[job.track_idx].title.clone();
                        st.log(format!("Download complete: {}", title)); 
                    } else {
                        track.retry_count += 1;
                        let retry_count = track.retry_count; 
                        if track.retry_count <= MAX_RETRIES {
                            track.status = TrackStatus::NotDownloaded;
                            let retry_at = tick + RETRY_BACKOFF * track.retry_count as u64;
                            st.log(format!("Download failed (attempt {}), retry at tick {}", retry_count, retry_at));
                            self.retry_queue.push(RetryEntry { track_idx: job.track_idx, retry_at });
                        } else {
                            track.status = TrackStatus::Failed;
                            drop(track);
                            st.log(format!("Download permanently failed after {} retries", MAX_RETRIES));
                        }
                    }
                }
                Ok(None) => { i += 1; }
                Err(_)   => { self.active.remove(i); }
            }
        }

        if self.active.len() >= MAX_PARALLEL { return; }

        // Priority: current → next → rest.
        let priority_order = {
            let st   = state.lock().unwrap();
            let cur  = st.current_idx;
            let next = st.next_idx();
            let mut order = vec![cur];
            if let Some(n) = next { if n != cur { order.push(n); } }
            for &idx in &st.play_order {
                if !order.contains(&idx) { order.push(idx); }
            }
            order
        };

        // Expire ready retry entries.
        self.retry_queue.retain(|r| r.retry_at > tick);

        for priority_idx in priority_order {
            if self.active.len() >= MAX_PARALLEL { break; }
            if self.active.iter().any(|j| j.track_idx == priority_idx) { continue; }

            let (status, url) = {
                let st = state.lock().unwrap();
                let t  = &st.tracks[priority_idx];
                (t.status.clone(), t.url.clone())
            };

            if status != TrackStatus::NotDownloaded { continue; }
            if self.retry_queue.iter().any(|r| r.track_idx == priority_idx) { continue; }

            let hash = url_hash(&url);
            let out  = PathBuf::from(format!("{}/{}.opus", CACHE_DIR, hash));

            if out.exists() {
                let mut st = state.lock().unwrap();
                st.tracks[priority_idx].local_path = Some(out.to_string_lossy().into_owned());
                st.tracks[priority_idx].status     = TrackStatus::Ready;
                continue;
            }

            self.evict_lru(state, priority_idx);

            {
                let mut st = state.lock().unwrap();
                st.tracks[priority_idx].status = TrackStatus::Downloading;
                let title = st.tracks[priority_idx].title.clone();
                st.log(format!("Starting download: {}", title));
            }

            match Command::new("yt-dlp")
                .args(["-x", "--audio-format", "opus", "--audio-quality", "0",
                       "--rate-limit", RATE_LIMIT, "-o", out.to_str().unwrap(), &url])
                .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
                .spawn()
            {
                Ok(child) => self.active.push(ActiveJob { track_idx: priority_idx, output_path: out, child }),
                Err(e) => {
                    let mut st = state.lock().unwrap();
                    st.tracks[priority_idx].status = TrackStatus::Failed;
                    st.log(format!("yt-dlp spawn failed: {}", e));
                }
            }
        }
    }

    fn evict_lru(&self, state: &Arc<Mutex<AppState>>, _for_idx: usize) {
        let total = cache_size_bytes();
        if total < MAX_CACHE_BYTES { return; }

        let pinned: Vec<String> = {
            let st = state.lock().unwrap();
            let mut p = Vec::new();
            if let Some(lp) = st.tracks[st.current_idx].local_path.clone() { p.push(lp); }
            if let Some(ni) = st.next_idx() {
                if let Some(lp) = st.tracks[ni].local_path.clone() { p.push(lp); }
            }
            p
        };

        let mut files: Vec<(PathBuf, SystemTime)> = Vec::new();
        if let Ok(rd) = fs::read_dir(CACHE_DIR) {
            for entry in rd.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("opus") {
                    if pinned.contains(&path.to_string_lossy().to_string()) { continue; }
                    if let Ok(meta) = fs::metadata(&path) {
                        files.push((path, meta.modified().unwrap_or(UNIX_EPOCH)));
                    }
                }
            }
        }

        files.sort_by_key(|(_, t)| *t);
        let mut freed = 0u64;
        for (path, _) in files {
            if total - freed < MAX_CACHE_BYTES { break; }
            if let Ok(meta) = fs::metadata(&path) {
                freed += meta.len();
                fs::remove_file(&path).ok();
                let path_str = path.to_string_lossy().to_string();
                let mut st = state.lock().unwrap();
                for track in st.tracks.iter_mut() {
                    if track.local_path.as_deref() == Some(&path_str) {
                        track.local_path  = None;
                        track.status      = TrackStatus::NotDownloaded;
                        track.retry_count = 0;
                    }
                }
            }
        }
    }
}

fn cache_size_bytes() -> u64 {
    let mut total = 0u64;
    if let Ok(rd) = fs::read_dir(CACHE_DIR) {
        for entry in rd.flatten() {
            if let Ok(meta) = fs::metadata(entry.path()) { total += meta.len(); }
        }
    }
    total
}
