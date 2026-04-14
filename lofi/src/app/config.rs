use serde::Deserialize;
use std::fs;
use crate::app::track::{Track, TrackStatus};

#[derive(Debug, Deserialize)]
pub struct Config {
    pub track: Vec<ConfigTrack>,
}

#[derive(Debug, Deserialize)]
pub struct ConfigTrack {
    pub title: String,
    pub url:   String,
}

impl Config {
    pub fn into_tracks(self) -> Vec<Track> {
        self.track
            .into_iter()
            .map(|t| Track {
                title:       t.title,
                url:         t.url,
                local_path:  None,
                status:      TrackStatus::NotDownloaded,
                resume_pos:  None,
                play_count:  0,
                retry_count: 0,
            })
            .collect()
    }
}

pub fn load_tracks(path: &str) -> Result<Vec<Track>, Box<dyn std::error::Error>> {
    let content = fs::read_to_string(path)?;
    let config: Config = toml::from_str(&content)?;
    Ok(config.into_tracks())
}
