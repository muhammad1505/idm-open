use crate::error::{CoreError, CoreResult};
use crate::net::NetClient;
use crate::task::{Task, TaskStatus};
use m3u8_rs::Playlist;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU8, Ordering};
use std::thread;
use std::time::Duration;
use url::Url;
use bytes::Bytes;

pub struct HlsDownloader;

impl HlsDownloader {
    pub fn download(
        task: &mut Task,
        net: Arc<dyn NetClient>,
        stop_flag: Arc<AtomicU8>,
        progress_updater: impl Fn(u64) + Send + 'static,
    ) -> CoreResult<TaskStatus> {
        // 1. Fetch Playlist
        let mut req = crate::net::DownloadRequest::new(task.url.clone(), "IDM-Open/1.0".to_string());
        req.headers = task.headers.clone();
        
        let response = net.get(&req)?;
        let bytes: Bytes = response.bytes().map_err(|e| CoreError::Network(e.to_string()))?;
        
        let playlist = match m3u8_rs::parse_playlist(&bytes) {
            Ok((_, p)) => p,
            Err(_) => return Err(CoreError::Network("Failed to parse m3u8 playlist".to_string())),
        };

        let media_playlist = match playlist {
            Playlist::MasterPlaylist(master) => {
                // Select best quality variant
                let best_variant = master
                    .variants
                    .iter()
                    .max_by_key(|v| v.bandwidth)
                    .ok_or(CoreError::Network("No variants in master playlist".to_string()))?;
                
                let variant_url = if best_variant.uri.starts_with("http") {
                    best_variant.uri.clone()
                } else {
                    Url::parse(&task.url)
                        .and_then(|u| u.join(&best_variant.uri))
                        .map(|u| u.to_string())
                        .map_err(|e| CoreError::Network(e.to_string()))?
                };

                // Fetch media playlist
                let var_req = crate::net::DownloadRequest::new(variant_url.clone(), "IDM-Open/1.0".to_string());
                let var_resp = net.get(&var_req)?;
                let var_bytes: Bytes = var_resp.bytes().map_err(|e| CoreError::Network(e.to_string()))?;
                
                match m3u8_rs::parse_playlist(&var_bytes) {
                    Ok((_, Playlist::MediaPlaylist(media))) => media,
                    _ => return Err(CoreError::Network("Failed to parse variant playlist".to_string())),
                }
            }
            Playlist::MediaPlaylist(media) => media,
        };

        // 2. Prepare Destination File
        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .append(true) // HLS appends segments
            .open(&task.dest_path)
            .map_err(|e| CoreError::Io(e.to_string()))?;

        // 3. Download Segments
        let base_url = Url::parse(&task.url).map_err(|e| CoreError::Network(e.to_string()))?;
        let mut downloaded_bytes = 0u64;

        for (i, segment) in media_playlist.segments.iter().enumerate() {
             if stop_flag.load(Ordering::SeqCst) != 0 {
                return Ok(TaskStatus::Paused); // Simplify stop handling for now
            }

            let seg_url = if segment.uri.starts_with("http") {
                segment.uri.clone()
            } else {
                base_url.join(&segment.uri).map(|u| u.to_string()).unwrap_or(segment.uri.clone())
            };

            // Retry logic for segment
            let mut success = false;
            for _ in 0..3 {
                let seg_req = crate::net::DownloadRequest::new(seg_url.clone(), "IDM-Open/1.0".to_string());
                if let Ok(resp) = net.get(&seg_req) {
                    let data: Bytes = match resp.bytes() {
                        Ok(b) => b,
                        Err(_) => continue,
                    };
                    if let Err(e) = file.write_all(&data) {
                         return Err(CoreError::Io(e.to_string()));
                    }
                    downloaded_bytes += data.len() as u64;
                    progress_updater(downloaded_bytes);
                    success = true;
                    break;
                }
                thread::sleep(Duration::from_millis(500));
            }

            if !success {
                return Err(CoreError::Network(format!("Failed to download segment {}", i)));
            }
        }

        Ok(TaskStatus::Completed)
    }
}
