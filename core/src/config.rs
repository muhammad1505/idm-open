#[derive(Debug, Clone)]
pub struct EngineConfig {
    pub max_concurrent_tasks: usize,
    pub max_segments_per_task: u32,
    pub min_segment_size_bytes: u64,
    pub global_speed_limit_bytes_per_sec: Option<u64>,
    pub per_task_speed_limit_bytes_per_sec: Option<u64>,
    pub user_agent: String,
    pub retry_count: u32,
    pub retry_backoff_secs: u64,
    pub progress_flush_bytes: u64,
    pub status_check_bytes: u64,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            max_concurrent_tasks: 4,
            max_segments_per_task: 8,
            min_segment_size_bytes: 2 * 1024 * 1024,
            global_speed_limit_bytes_per_sec: None,
            per_task_speed_limit_bytes_per_sec: None,
            user_agent: "IDM-Open/0.1".to_string(),
            retry_count: 5,
            retry_backoff_secs: 3,
            progress_flush_bytes: 1024 * 1024,
            status_check_bytes: 512 * 1024,
        }
    }
}
