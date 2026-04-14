use crate::app::track::Track;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum UiLayout { Classic, Compact }

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RepeatMode { None, All, One }

impl RepeatMode {
    pub fn label(self) -> &'static str {
        match self { RepeatMode::None => "─", RepeatMode::All => "↺", RepeatMode::One => "↻" }
    }
    pub fn next(self) -> RepeatMode {
        match self { RepeatMode::None => RepeatMode::All, RepeatMode::All => RepeatMode::One, RepeatMode::One => RepeatMode::None }
    }
}

/// Search overlay state — only active when `open` is true.
#[derive(Debug, Clone, Default)]
pub struct SearchState {
    pub open:    bool,
    pub query:   String,
    pub cursor:  usize,
    pub results: Vec<usize>,  // track indices matching query
}

impl SearchState {
    pub fn filter(&mut self, tracks: &[Track]) {
        let q = self.query.to_lowercase();
        self.results = tracks.iter()
            .enumerate()
            .filter(|(_, t)| t.title.to_lowercase().contains(&q))
            .map(|(i, _)| i)
            .collect();
        self.cursor = self.cursor.min(self.results.len().saturating_sub(1));
    }
}

#[derive(Debug, Clone)]
pub struct AppState {
    pub tracks:      Vec<Track>,
    pub current_idx: usize,
    pub play_order:  Vec<usize>,
    pub play_pos:    usize,

    pub is_playing:  bool,
    pub is_running:  bool,
    pub shuffle:     bool,
    pub repeat:      RepeatMode,
    pub volume:      u8,

    pub time_pos:    Option<f64>,
    pub duration:    Option<f64>,
    pub buffered:    Option<f64>,

    pub layout:      UiLayout,
    pub status_msg:  String,
    pub search:      SearchState,

    pub debug:       bool,
    pub debug_log:   Vec<String>,
    pub tick:        u64,
}

impl AppState {
    pub fn new(tracks: Vec<Track>, layout: UiLayout) -> Self {
        let n = tracks.len();
        Self {
            play_order:  (0..n).collect(),
            play_pos:    0,
            current_idx: 0,
            tracks,
            is_playing:  true,
            is_running:  true,
            shuffle:     false,
            repeat:      RepeatMode::None,
            volume:      100,
            time_pos:    None,
            duration:    None,
            buffered:    None,
            layout,
            status_msg:  String::from("> Meow Meow \u{1F431} ..."),
            search:      SearchState::default(),
            debug:       false,
            debug_log:   Vec::new(),
            tick:        0,
        }
    }

    pub fn current_track(&self) -> Option<&Track> { self.tracks.get(self.current_idx) }

    pub fn log(&mut self, msg: impl Into<String>) {
        if self.debug_log.len() >= 64 { self.debug_log.remove(0); }
        self.debug_log.push(msg.into());
    }

    pub fn advance_track(&mut self) -> bool {
        self.clear_playback();
        if self.repeat == RepeatMode::One { return true; }
        let next = self.play_pos + 1;
        if next < self.play_order.len() {
            self.play_pos = next; self.current_idx = self.play_order[next]; true
        } else if self.repeat == RepeatMode::All {
            self.play_pos = 0; self.current_idx = self.play_order[0]; true
        } else { false }
    }

    pub fn prev_track(&mut self) -> bool {
        self.clear_playback();
        if self.play_pos > 0 {
            self.play_pos -= 1; self.current_idx = self.play_order[self.play_pos]; true
        } else if self.repeat == RepeatMode::All {
            let last = self.play_order.len() - 1;
            self.play_pos = last; self.current_idx = self.play_order[last]; true
        } else { false }
    }

    /// Jump directly to a track index (from search). Disables shuffle.
    pub fn jump_to(&mut self, idx: usize) {
        self.clear_playback();
        self.shuffle     = false;
        self.play_order  = (0..self.tracks.len()).collect();
        self.play_pos    = idx;
        self.current_idx = idx;
    }

    pub fn rebuild_order(&mut self) {
        if self.shuffle {
            let n = self.tracks.len();
            let mut order: Vec<usize> = (0..n).collect();
            let mut seed = self.tick ^ 0xdeadbeef;
            for i in (1..n).rev() {
                seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
                let j = (seed >> 33) as usize % (i + 1);
                order.swap(i, j);
            }
            if let Some(pos) = order.iter().position(|&x| x == self.current_idx) {
                order.swap(0, pos);
            }
            self.play_order = order;
            self.play_pos   = 0;
        } else {
            self.play_order  = (0..self.tracks.len()).collect();
            self.play_pos    = self.current_idx;
        }
    }

    pub fn next_idx(&self) -> Option<usize> {
        let next = self.play_pos + 1;
        if next < self.play_order.len() { Some(self.play_order[next]) } else { None }
    }

    fn clear_playback(&mut self) {
        self.time_pos = None; self.duration = None; self.buffered = None;
    }
}
