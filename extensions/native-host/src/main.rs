use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use idm_core::config::EngineConfig;
use idm_core::storage::SqliteStorage;
use idm_core::DownloadEngine;

#[derive(Debug, Deserialize)]
struct NativeRequest {
    url: String,
    dest_path: Option<String>,
}

#[derive(Debug, Serialize)]
struct NativeResponse {
    ok: bool,
    id: Option<String>,
    error: Option<String>,
}

fn main() {
    let engine = match build_engine() {
        Ok(engine) => engine,
        Err(err) => {
            let _ = write_response(&NativeResponse {
                ok: false,
                id: None,
                error: Some(err),
            });
            return;
        }
    };

    loop {
        match read_message() {
            Ok(Some(bytes)) => match handle_message(&engine, &bytes) {
                Ok(resp) => {
                    let _ = write_response(&resp);
                }
                Err(err) => {
                    let _ = write_response(&NativeResponse {
                        ok: false,
                        id: None,
                        error: Some(err),
                    });
                }
            },
            Ok(None) => break,
            Err(err) => {
                let _ = write_response(&NativeResponse {
                    ok: false,
                    id: None,
                    error: Some(err.to_string()),
                });
                break;
            }
        }
    }
}

fn build_engine() -> Result<DownloadEngine, String> {
    let mut engine = DownloadEngine::new(EngineConfig::default());
    let db_path = match env::var("IDM_DB") {
        Ok(path) => path,
        Err(_) => default_db_path().to_string_lossy().to_string(),
    };

    let storage = SqliteStorage::new(db_path).map_err(|err| err.to_string())?;
    engine = engine.with_storage(Box::new(storage));
    Ok(engine)
}

fn handle_message(engine: &DownloadEngine, bytes: &[u8]) -> Result<NativeResponse, String> {
    let request: NativeRequest =
        serde_json::from_slice(bytes).map_err(|err| err.to_string())?;
    if request.url.trim().is_empty() {
        return Err("url is required".to_string());
    }

    let dest_path = request
        .dest_path
        .unwrap_or_else(|| default_dest_path(&request.url));

    let id = engine
        .add_task(request.url, dest_path)
        .map_err(|err| err.to_string())?;

    Ok(NativeResponse {
        ok: true,
        id: Some(id.to_string()),
        error: None,
    })
}

fn read_message() -> io::Result<Option<Vec<u8>>> {
    let mut len_buf = [0u8; 4];
    let mut stdin = io::stdin();
    if let Err(err) = stdin.read_exact(&mut len_buf) {
        if err.kind() == io::ErrorKind::UnexpectedEof {
            return Ok(None);
        }
        return Err(err);
    }
    let len = u32::from_le_bytes(len_buf) as usize;
    let mut buf = vec![0u8; len];
    stdin.read_exact(&mut buf)?;
    Ok(Some(buf))
}

fn write_response(resp: &NativeResponse) -> io::Result<()> {
    let payload = serde_json::to_vec(resp).unwrap_or_else(|_| b"{}".to_vec());
    let len = (payload.len() as u32).to_le_bytes();
    let mut stdout = io::stdout();
    stdout.write_all(&len)?;
    stdout.write_all(&payload)?;
    stdout.flush()?;
    Ok(())
}

fn default_db_path() -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let dir = PathBuf::from(home).join(".idm-open");
    let _ = fs::create_dir_all(&dir);
    dir.join("idm.db")
}

fn default_dest_path(url: &str) -> String {
    let filename = filename_from_url(url);
    let dir = download_dir();
    dir.join(filename).to_string_lossy().to_string()
}

fn download_dir() -> PathBuf {
    if let Ok(dir) = env::var("IDM_DOWNLOAD_DIR") {
        return PathBuf::from(dir);
    }
    let shared = PathBuf::from("/storage/emulated/0/Download");
    if shared.exists() {
        return shared;
    }
    let sdcard = PathBuf::from("/sdcard/Download");
    if sdcard.exists() {
        return sdcard;
    }
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let downloads = PathBuf::from(&home).join("Downloads");
    if downloads.exists() {
        return downloads;
    }
    let downloads_lower = PathBuf::from(&home).join("downloads");
    if downloads_lower.exists() {
        return downloads_lower;
    }
    PathBuf::from("/tmp")
}

fn filename_from_url(url: &str) -> String {
    let trimmed = url.split('?').next().unwrap_or(url);
    let name = trimmed.rsplit('/').next().unwrap_or("download.bin");
    if name.is_empty() {
        "download.bin".to_string()
    } else {
        name.to_string()
    }
}
