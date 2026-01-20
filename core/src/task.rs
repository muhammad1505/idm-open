use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::checksum::ChecksumRequest;

pub type TaskId = Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum TaskStatus {
    Queued,
    Active,
    Paused,
    Completed,
    Failed,
    Canceled,
}

impl TaskStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            TaskStatus::Queued => "queued",
            TaskStatus::Active => "active",
            TaskStatus::Paused => "paused",
            TaskStatus::Completed => "completed",
            TaskStatus::Failed => "failed",
            TaskStatus::Canceled => "canceled",
        }
    }

    pub fn from_str(value: &str) -> Option<Self> {
        match value {
            "queued" => Some(TaskStatus::Queued),
            "active" => Some(TaskStatus::Active),
            "paused" => Some(TaskStatus::Paused),
            "completed" => Some(TaskStatus::Completed),
            "failed" => Some(TaskStatus::Failed),
            "canceled" => Some(TaskStatus::Canceled),
            _ => None,
        }
    }
}

impl fmt::Display for TaskStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: TaskId,
    pub url: String,
    pub dest_path: String,
    pub status: TaskStatus,
    pub priority: i32,
    pub total_bytes: u64,
    pub downloaded_bytes: u64,
    pub headers: HashMap<String, String>,
    pub cookies: HashMap<String, String>,
    pub mirrors: Vec<String>,
    pub checksum: Option<ChecksumRequest>,
    pub proxy_url: Option<String>,
    pub auth_user: Option<String>,
    pub auth_pass: Option<String>,
    pub created_at: u64,
    pub updated_at: u64,
    pub error: Option<String>,
}

impl Task {
    pub fn new(url: String, dest_path: String) -> Self {
        let now = now_epoch();
        Self {
            id: Uuid::new_v4(),
            url,
            dest_path,
            status: TaskStatus::Queued,
            priority: 0,
            total_bytes: 0,
            downloaded_bytes: 0,
            headers: HashMap::new(),
            cookies: HashMap::new(),
            mirrors: Vec::new(),
            checksum: None,
            proxy_url: None,
            auth_user: None,
            auth_pass: None,
            created_at: now,
            updated_at: now,
            error: None,
        }
    }

    pub fn touch(&mut self) {
        self.updated_at = now_epoch();
    }

    pub fn url_candidates(&self) -> Vec<String> {
        let mut urls = Vec::with_capacity(1 + self.mirrors.len());
        urls.push(self.url.clone());
        for mirror in &self.mirrors {
            if mirror != &self.url {
                urls.push(mirror.clone());
            }
        }
        urls
    }
}

fn now_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}
