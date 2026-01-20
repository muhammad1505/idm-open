use std::collections::HashMap;
use std::env;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use idm_core::config::EngineConfig;
use idm_core::storage::SqliteStorage;
use idm_core::{DownloadEngine, TaskId, TaskStatus};

fn main() {
    let engine = match build_engine() {
        Ok(engine) => engine,
        Err(err) => {
            eprintln!("error: {}", err);
            return;
        }
    };
    let engine = Arc::new(engine);

    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        return;
    }

    match args[1].as_str() {
        "add" => {
            let url = match args.get(2) {
                Some(value) => value.to_string(),
                None => {
                    print_usage();
                    return;
                }
            };
            let dest = args.get(3).map(|value| value.to_string()).unwrap_or_default();
            if dest.is_empty() {
                println!("dest kosong, nama file akan diambil otomatis");
            }
            match engine.add_task(url, dest) {
                Ok(id) => println!("added task: {}", id),
                Err(err) => eprintln!("error: {}", err),
            }
        }
        "list" => match engine.list_tasks() {
            Ok(tasks) => {
                for task in tasks {
                    println!("{}\t{}\t{}", task.id, task.status, task.url);
                }
            }
            Err(err) => eprintln!("error: {}", err),
        },
        "start-next" => {
            if let Err(err) = engine.enqueue_queued() {
                eprintln!("error: {}", err);
                return;
            }
            let (handle, stop) = spawn_progress(Arc::clone(&engine));
            match engine.start_next() {
                Ok(Some(id)) => {
                    println!("started task: {}", id);
                    engine.wait_all();
                }
                Ok(None) => println!("no queued tasks"),
                Err(err) => eprintln!("error: {}", err),
            }
            stop.store(true, Ordering::SeqCst);
            let _ = handle.join();
        },
        "run" => {
            if let Err(err) = engine.enqueue_queued() {
                eprintln!("error: {}", err);
                return;
            }
            let (handle, stop) = spawn_progress(Arc::clone(&engine));
            match engine.run() {
                Ok(()) => println!("queue complete"),
                Err(err) => eprintln!("error: {}", err),
            }
            stop.store(true, Ordering::SeqCst);
            let _ = handle.join();
        },
        "pause" => run_with_id(engine.as_ref(), &args, 2, |engine, id| engine.pause_task(id)),
        "resume" => run_with_id(engine.as_ref(), &args, 2, |engine, id| engine.resume_task(id)),
        "cancel" => run_with_id(engine.as_ref(), &args, 2, |engine, id| engine.cancel_task(id)),
        _ => print_usage(),
    }
}

fn build_engine() -> Result<DownloadEngine, idm_core::CoreError> {
    let mut engine = DownloadEngine::new(EngineConfig::default());
    if let Ok(path) = env::var("IDM_DB") {
        let storage = SqliteStorage::new(path)?;
        engine = engine.with_storage(Box::new(storage));
    }
    Ok(engine)
}

fn run_with_id<F>(engine: &DownloadEngine, args: &[String], idx: usize, f: F)
where
    F: FnOnce(&DownloadEngine, &TaskId) -> Result<(), idm_core::CoreError>,
{
    let id = match args.get(idx) {
        Some(value) => value,
        None => {
            print_usage();
            return;
        }
    };

    let task_id = match TaskId::parse_str(id) {
        Ok(value) => value,
        Err(_) => {
            eprintln!("invalid task id");
            return;
        }
    };

    if let Err(err) = f(engine, &task_id) {
        eprintln!("error: {}", err);
    }
}

fn print_usage() {
    eprintln!(
        "Usage: idm-cli <command> [args]\n\
Commands:\n\
  add <url> [dest]     Add a task (dest optional)\n\
  list                 List tasks\n\
  start-next           Start next queued task and wait\n\
  run                  Run queued tasks until complete\n\
  pause <id>           Pause a task\n\
  resume <id>          Resume a task\n\
  cancel <id>          Cancel a task\n\
Environment:\n\
  IDM_DB=/path/to/db   Persist tasks in SQLite\n\
  IDM_DOWNLOAD_DIR     Default download dir when dest missing"
    );
}

fn spawn_progress(engine: Arc<DownloadEngine>) -> (thread::JoinHandle<()>, Arc<AtomicBool>) {
    let stop = Arc::new(AtomicBool::new(false));
    let stop_clone = Arc::clone(&stop);
    let handle = thread::spawn(move || {
        let mut last: HashMap<TaskId, (u64, Instant)> = HashMap::new();
        loop {
            if stop_clone.load(Ordering::SeqCst) {
                break;
            }
            if let Ok(tasks) = engine.list_tasks() {
                let mut lines = Vec::new();
                let now = Instant::now();
                for task in tasks {
                    if task.status != TaskStatus::Active && task.status != TaskStatus::Queued {
                        continue;
                    }
                    let total = task.total_bytes;
                    let downloaded = task.downloaded_bytes;
                    let percent = if total > 0 {
                        format!("{:.1}%", (downloaded as f64 / total as f64) * 100.0)
                    } else {
                        "--".to_string()
                    };
                    let (speed, last_time) = last
                        .get(&task.id)
                        .cloned()
                        .unwrap_or((downloaded, now));
                    let delta_bytes = downloaded.saturating_sub(speed);
                    let delta_secs = now.duration_since(last_time).as_secs_f64();
                    let speed_bps = if delta_secs > 0.0 {
                        (delta_bytes as f64 / delta_secs) as u64
                    } else {
                        0
                    };
                    last.insert(task.id, (downloaded, now));
                    let name = Path::new(&task.dest_path)
                        .file_name()
                        .and_then(|value| value.to_str())
                        .unwrap_or("download");
                    let remaining = total.saturating_sub(downloaded);
                    let eta = if total > 0 && speed_bps > 0 {
                        format_duration(remaining / speed_bps)
                    } else {
                        "--:--".to_string()
                    };
                    let line = format!(
                        "[{}] {} {} {}/{} ({}/s) eta {}",
                        task.status,
                        &task.id.to_string()[..8],
                        percent,
                        format_bytes(downloaded),
                        if total > 0 { format_bytes(total) } else { "?".to_string() },
                        format_bytes(speed_bps),
                        eta,
                    );
                    lines.push(format!("{} {}", line, name));
                }
                if !lines.is_empty() {
                    for line in lines {
                        println!("{}", line);
                    }
                }
            }
            thread::sleep(Duration::from_secs(1));
        }
    });
    (handle, stop)
}

fn format_bytes(bytes: u64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    let b = bytes as f64;
    if b >= GB {
        format!("{:.2}GB", b / GB)
    } else if b >= MB {
        format!("{:.2}MB", b / MB)
    } else if b >= KB {
        format!("{:.2}KB", b / KB)
    } else {
        format!("{}B", bytes)
    }
}

fn format_duration(mut seconds: u64) -> String {
    let hours = seconds / 3600;
    seconds %= 3600;
    let minutes = seconds / 60;
    let secs = seconds % 60;
    if hours > 0 {
        format!("{:02}:{:02}:{:02}", hours, minutes, secs)
    } else {
        format!("{:02}:{:02}", minutes, secs)
    }
}
