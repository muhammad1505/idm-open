use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct ThrottleConfig {
    pub global_limit_bytes_per_sec: Option<u64>,
    pub per_task_limit_bytes_per_sec: Option<u64>,
}

impl Default for ThrottleConfig {
    fn default() -> Self {
        Self {
            global_limit_bytes_per_sec: None,
            per_task_limit_bytes_per_sec: None,
        }
    }
}

#[derive(Debug)]
struct ThrottleState {
    start: Instant,
    bytes: u64,
    limit_bytes_per_sec: u64,
}

impl ThrottleState {
    fn new(limit_bytes_per_sec: u64) -> Self {
        Self {
            start: Instant::now(),
            bytes: 0,
            limit_bytes_per_sec,
        }
    }

    fn reserve_sleep(&mut self, bytes: u64) -> Duration {
        self.bytes = self.bytes.saturating_add(bytes);
        if self.limit_bytes_per_sec == 0 {
            return Duration::from_secs(0);
        }
        let expected = self.bytes as f64 / self.limit_bytes_per_sec as f64;
        let elapsed = self.start.elapsed().as_secs_f64();
        if expected > elapsed {
            Duration::from_secs_f64(expected - elapsed)
        } else {
            Duration::from_secs(0)
        }
    }
}

#[derive(Clone)]
pub struct Throttle {
    global: Option<std::sync::Arc<Mutex<ThrottleState>>>,
    per_task: Option<std::sync::Arc<Mutex<ThrottleState>>>,
}

impl Throttle {
    pub fn new(global_limit: Option<u64>, per_task_limit: Option<u64>) -> Self {
        let global = global_limit.map(|limit| std::sync::Arc::new(Mutex::new(ThrottleState::new(limit))));
        let per_task = per_task_limit.map(|limit| std::sync::Arc::new(Mutex::new(ThrottleState::new(limit))));
        Self { global, per_task }
    }

    pub fn throttle(&self, bytes: u64) {
        let mut max_sleep = Duration::from_secs(0);
        if let Some(state) = &self.global {
            if let Ok(mut guard) = state.lock() {
                let sleep = guard.reserve_sleep(bytes);
                if sleep > max_sleep {
                    max_sleep = sleep;
                }
            }
        }
        if let Some(state) = &self.per_task {
            if let Ok(mut guard) = state.lock() {
                let sleep = guard.reserve_sleep(bytes);
                if sleep > max_sleep {
                    max_sleep = sleep;
                }
            }
        }
        if max_sleep.as_millis() > 0 {
            std::thread::sleep(max_sleep);
        }
    }
}
