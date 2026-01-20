use std::env;
use std::thread;
use std::time::Duration;

use idm_core::config::EngineConfig;
use idm_core::storage::SqliteStorage;
use idm_core::DownloadEngine;

fn main() {
    let config = EngineConfig::default();
    let engine = match build_engine(config) {
        Ok(engine) => engine,
        Err(err) => {
            eprintln!("error: {}", err);
            return;
        }
    };

    let (interval_secs, once) = parse_args();

    loop {
        if let Err(err) = engine.enqueue_queued() {
            eprintln!("error: {}", err);
        }
        if let Err(err) = engine.run() {
            eprintln!("error: {}", err);
        }
        if once {
            break;
        }
        thread::sleep(Duration::from_secs(interval_secs));
    }
}

fn build_engine(config: EngineConfig) -> Result<DownloadEngine, idm_core::CoreError> {
    let mut engine = DownloadEngine::new(config);
    let db_path = env::var("IDM_DB").unwrap_or_else(|_| "./idm.db".to_string());
    let storage = SqliteStorage::new(db_path)?;
    engine = engine.with_storage(Box::new(storage));
    Ok(engine)
}

fn parse_args() -> (u64, bool) {
    let mut interval_secs = 2u64;
    let mut once = false;
    let mut args = env::args().skip(1);

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--interval" => {
                if let Some(value) = args.next() {
                    if let Ok(parsed) = value.parse::<u64>() {
                        interval_secs = parsed.max(1);
                    }
                }
            }
            "--once" => {
                once = true;
            }
            _ => {}
        }
    }

    (interval_secs, once)
}
