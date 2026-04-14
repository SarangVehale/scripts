use std::process::{Child, Command, Stdio};

pub const IPC_SOCKET: &str = "/tmp/lofi-mpv.sock";

pub struct MpvPlayer {
    process: Option<Child>,
}

impl MpvPlayer {
    pub fn new() -> Self { Self { process: None } }

    pub fn play(&mut self, source: &str) -> bool {
        self.stop();
        let ipc = format!("--input-ipc-server={}", IPC_SOCKET);
        match Command::new("mpv")
            .args([source, "--no-video", "--quiet", "--cache=yes",
                   "--demuxer-max-bytes=50MiB", "--demuxer-readahead-secs=60", &ipc])
            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => { self.process = Some(c); true }
            Err(_) => false,
        }
    }

    pub fn play_from(&mut self, source: &str, pos: f64) -> bool {
        self.stop();
        let ipc  = format!("--input-ipc-server={}", IPC_SOCKET);
        let seek = format!("--start={:.1}", pos);
        match Command::new("mpv")
            .args([source, "--no-video", "--quiet", "--cache=yes",
                   "--demuxer-max-bytes=50MiB", "--demuxer-readahead-secs=60",
                   &seek, &ipc])
            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => { self.process = Some(c); true }
            Err(_) => false,
        }
    }

    pub fn is_alive(&mut self) -> bool {
        self.process.as_mut()
            .map(|c| matches!(c.try_wait(), Ok(None)))
            .unwrap_or(false)
    }

    pub fn stop(&mut self) {
        if let Some(mut c) = self.process.take() {
            let _ = c.kill();
            let _ = c.wait();
        }
    }
}

impl Drop for MpvPlayer {
    fn drop(&mut self) { self.stop(); }
}
