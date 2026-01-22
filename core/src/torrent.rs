use crate::error::{CoreError, CoreResult};
use lava_torrent::torrent::v1::Torrent;

pub struct TorrentEngine;

impl TorrentEngine {
    pub fn new() -> Self {
        Self
    }

    pub fn parse_file(path: &str) -> CoreResult<TorrentInfo> {
        let torrent = Torrent::read_from_file(path)
            .map_err(|e| CoreError::Io(format!("Invalid torrent file: {:?}", e)))?;
        
        // Calculate hash BEFORE moving fields (like torrent.name)
        let hash = torrent.info_hash();

        Ok(TorrentInfo {
            name: torrent.name,
            length: torrent.length,
            info_hash: hash,
        })
    }
}

pub struct TorrentInfo {
    pub name: String,
    pub length: i64,
    pub info_hash: String,
}