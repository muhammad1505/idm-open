use crate::error::{CoreError, CoreResult};
use lava_torrent::torrent::v1::Torrent;
use std::path::Path;

pub struct TorrentEngine;

impl TorrentEngine {
    pub fn new() -> Self {
        Self
    }

    pub fn parse_file(path: &str) -> CoreResult<TorrentInfo> {
        let torrent = Torrent::read_from_file(path)
            .map_err(|e| CoreError::Io(format!("Invalid torrent file: {:?}", e)))?;
        
        Ok(TorrentInfo {
            name: torrent.name,
            length: torrent.length,
            info_hash: torrent.info_hash(),
        })
    }
}

pub struct TorrentInfo {
    pub name: String,
    pub length: i64,
    pub info_hash: String,
}
