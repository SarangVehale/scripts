#[derive(Debug, Clone, PartialEq)]
pub struct Track {
    pub title:       String,
    pub url:         String,
    pub local_path:  Option<String>,
    pub status:      TrackStatus,
    pub resume_pos:  Option<f64>,
    pub play_count:  u32,  // for future smart ordering
    pub retry_count: u8,   // failed download retries attempted
}

#[derive(Debug, Clone, PartialEq)]
pub enum TrackStatus {
    NotDownloaded,
    Downloading,
    Ready,
    Failed,
}

impl Track {
    pub fn cache_label(&self) -> &'static str {
        match self.status {
            TrackStatus::NotDownloaded => "○",
            TrackStatus::Downloading   => "↓",
            TrackStatus::Ready         => "✓",
            TrackStatus::Failed        => "✗",
        }
    }
}
