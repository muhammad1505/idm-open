use crate::error::{CoreError, CoreResult};
use m3u8_rs::{MasterPlaylist, MediaPlaylist, Playlist};
use std::io::Read;
use url::Url;

pub struct HlsDownloader;

impl HlsDownloader {
    pub fn parse_playlist(content: &[u8]) -> CoreResult<Playlist> {
        match m3u8_rs::parse_playlist(content) {
            Ok((_, playlist)) => Ok(playlist),
            Err(_) => Err(CoreError::Network("Failed to parse m3u8 playlist".to_string())),
        }
    }

    pub fn select_best_variant(master: &MasterPlaylist) -> Option<String> {
        master
            .variants
            .iter()
            .max_by_key(|v| v.bandwidth)
            .map(|v| v.uri.clone())
    }

    pub fn extract_segments(media: &MediaPlaylist, base_url: &str) -> Vec<String> {
        media
            .segments
            .iter()
            .map(|s| {
                if s.uri.starts_with("http") {
                    s.uri.clone()
                } else {
                    match Url::parse(base_url).and_then(|u| u.join(&s.uri)) {
                        Ok(u) => u.to_string(),
                        Err(_) => s.uri.clone(),
                    }
                }
            })
            .collect()
    }
}
