use std::collections::HashMap;

use crate::checksum::{ChecksumRequest, ChecksumType};
use crate::error::{CoreError, CoreResult};
use crate::segment::{Segment, SegmentStatus};
use crate::task::{Task, TaskId, TaskStatus};

#[cfg(feature = "sqlite")]
use rusqlite::params;

pub trait Storage: Send + Sync {
    fn save_task(&mut self, task: &Task) -> CoreResult<()>;
    fn load_task(&self, id: &TaskId) -> CoreResult<Task>;
    fn list_tasks(&self) -> CoreResult<Vec<Task>>;
    fn delete_task(&mut self, id: &TaskId) -> CoreResult<()>;

    fn save_segments(&mut self, task_id: &TaskId, segments: &[Segment]) -> CoreResult<()>;
    fn load_segments(&self, task_id: &TaskId) -> CoreResult<Vec<Segment>>;
}

#[derive(Default)]
pub struct MemoryStorage {
    tasks: HashMap<TaskId, Task>,
    segments: HashMap<TaskId, Vec<Segment>>,
}

impl Storage for MemoryStorage {
    fn save_task(&mut self, task: &Task) -> CoreResult<()> {
        self.tasks.insert(task.id, task.clone());
        Ok(())
    }

    fn load_task(&self, id: &TaskId) -> CoreResult<Task> {
        self.tasks
            .get(id)
            .cloned()
            .ok_or_else(|| CoreError::NotFound(id.to_string()))
    }

    fn list_tasks(&self) -> CoreResult<Vec<Task>> {
        Ok(self.tasks.values().cloned().collect())
    }

    fn delete_task(&mut self, id: &TaskId) -> CoreResult<()> {
        self.tasks.remove(id);
        self.segments.remove(id);
        Ok(())
    }

    fn save_segments(&mut self, task_id: &TaskId, segments: &[Segment]) -> CoreResult<()> {
        self.segments.insert(*task_id, segments.to_vec());
        Ok(())
    }

    fn load_segments(&self, task_id: &TaskId) -> CoreResult<Vec<Segment>> {
        Ok(self
            .segments
            .get(task_id)
            .cloned()
            .unwrap_or_default())
    }
}

#[cfg(feature = "sqlite")]
pub struct SqliteStorage {
    pub path: String,
}

#[cfg(feature = "sqlite")]
impl SqliteStorage {
    pub fn new(path: impl Into<String>) -> CoreResult<Self> {
        let storage = Self { path: path.into() };
        storage.init()?;
        Ok(storage)
    }

    fn conn(&self) -> CoreResult<rusqlite::Connection> {
        rusqlite::Connection::open(&self.path)
            .map_err(|err| CoreError::Storage(err.to_string()))
    }

    fn init(&self) -> CoreResult<()> {
        let conn = self.conn()?;
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                url TEXT NOT NULL,
                dest_path TEXT NOT NULL,
                status TEXT NOT NULL,
                priority INTEGER NOT NULL DEFAULT 0,
                total_bytes INTEGER DEFAULT 0,
                downloaded_bytes INTEGER DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                error TEXT,
                checksum_type TEXT,
                checksum_hex TEXT,
                proxy_url TEXT,
                auth_user TEXT,
                auth_pass TEXT
            );
            CREATE TABLE IF NOT EXISTS segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT NOT NULL,
                segment_index INTEGER NOT NULL,
                range_start INTEGER NOT NULL,
                range_end INTEGER NOT NULL,
                downloaded_bytes INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            CREATE TABLE IF NOT EXISTS headers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT NOT NULL,
                name TEXT NOT NULL,
                value TEXT NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            CREATE TABLE IF NOT EXISTS cookies (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT NOT NULL,
                name TEXT NOT NULL,
                value TEXT NOT NULL,
                domain TEXT,
                path TEXT,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            CREATE TABLE IF NOT EXISTS mirrors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT NOT NULL,
                url TEXT NOT NULL,
                rank INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                payload TEXT,
                created_at INTEGER NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id)
            );
            ",
        )
        .map_err(|err| CoreError::Storage(err.to_string()))?;
        Ok(())
    }
}

#[cfg(feature = "sqlite")]
impl Storage for SqliteStorage {
    fn save_task(&mut self, task: &Task) -> CoreResult<()> {
        let mut conn = self.conn()?;
        let tx = conn
            .transaction()
            .map_err(|err| CoreError::Storage(err.to_string()))?;

        let (checksum_type, checksum_hex) = match &task.checksum {
            Some(req) => (Some(req.checksum_type.as_str()), Some(req.expected_hex.as_str())),
            None => (None, None),
        };

        tx.execute(
            "
            INSERT INTO tasks (
                id, url, dest_path, status, priority, total_bytes, downloaded_bytes,
                created_at, updated_at, error, checksum_type, checksum_hex, proxy_url,
                auth_user, auth_pass
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
            ON CONFLICT(id) DO UPDATE SET
                url=excluded.url,
                dest_path=excluded.dest_path,
                status=excluded.status,
                priority=excluded.priority,
                total_bytes=excluded.total_bytes,
                downloaded_bytes=excluded.downloaded_bytes,
                created_at=excluded.created_at,
                updated_at=excluded.updated_at,
                error=excluded.error,
                checksum_type=excluded.checksum_type,
                checksum_hex=excluded.checksum_hex,
                proxy_url=excluded.proxy_url,
                auth_user=excluded.auth_user,
                auth_pass=excluded.auth_pass
            ",
            params![
                task.id.to_string(),
                task.url.as_str(),
                task.dest_path.as_str(),
                task.status.as_str(),
                task.priority,
                task.total_bytes as i64,
                task.downloaded_bytes as i64,
                task.created_at as i64,
                task.updated_at as i64,
                task.error.as_deref(),
                checksum_type,
                checksum_hex,
                task.proxy_url.as_deref(),
                task.auth_user.as_deref(),
                task.auth_pass.as_deref(),
            ],
        )
        .map_err(|err| CoreError::Storage(err.to_string()))?;

        tx.execute("DELETE FROM headers WHERE task_id = ?1", params![task.id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        for (name, value) in &task.headers {
            tx.execute(
                "INSERT INTO headers (task_id, name, value) VALUES (?1, ?2, ?3)",
                params![task.id.to_string(), name, value],
            )
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        }

        tx.execute("DELETE FROM cookies WHERE task_id = ?1", params![task.id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        for (name, value) in &task.cookies {
            tx.execute(
                "INSERT INTO cookies (task_id, name, value, domain, path) VALUES (?1, ?2, ?3, NULL, NULL)",
                params![task.id.to_string(), name, value],
            )
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        }

        tx.execute("DELETE FROM mirrors WHERE task_id = ?1", params![task.id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        for (rank, url) in task.mirrors.iter().enumerate() {
            tx.execute(
                "INSERT INTO mirrors (task_id, url, rank) VALUES (?1, ?2, ?3)",
                params![task.id.to_string(), url, rank as i64],
            )
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        }

        tx.commit()
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        Ok(())
    }

    fn load_task(&self, id: &TaskId) -> CoreResult<Task> {
        use rusqlite::{params, OptionalExtension};

        let conn = self.conn()?;
        let mut stmt = conn
            .prepare(
                "
                SELECT id, url, dest_path, status, priority, total_bytes, downloaded_bytes,
                       created_at, updated_at, error, checksum_type, checksum_hex, proxy_url,
                       auth_user, auth_pass
                FROM tasks WHERE id = ?1
                ",
            )
            .map_err(|err| CoreError::Storage(err.to_string()))?;

        let task = stmt
            .query_row(params![id.to_string()], |row| {
                let status: String = row.get(3)?;
                let status = TaskStatus::from_str(&status)
                    .ok_or_else(|| rusqlite::Error::InvalidQuery)?;
                let checksum_type: Option<String> = row.get(10)?;
                let checksum_hex: Option<String> = row.get(11)?;
                let checksum = match (checksum_type, checksum_hex) {
                    (Some(t), Some(hex)) => ChecksumType::from_str(&t)
                        .map(|checksum_type| ChecksumRequest {
                            checksum_type,
                            expected_hex: hex,
                        }),
                    _ => None,
                };

                Ok(Task {
                    id: TaskId::parse_str(row.get::<_, String>(0)?.as_str())
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                    url: row.get(1)?,
                    dest_path: row.get(2)?,
                    status,
                    priority: row.get(4)?,
                    total_bytes: row.get::<_, i64>(5)? as u64,
                    downloaded_bytes: row.get::<_, i64>(6)? as u64,
                    headers: HashMap::new(),
                    cookies: HashMap::new(),
                    mirrors: Vec::new(),
                    checksum,
                    proxy_url: row.get(12)?,
                    auth_user: row.get(13)?,
                    auth_pass: row.get(14)?,
                    created_at: row.get::<_, i64>(7)? as u64,
                    updated_at: row.get::<_, i64>(8)? as u64,
                    error: row.get(9)?,
                })
            })
            .optional()
            .map_err(|err| CoreError::Storage(err.to_string()))?;

        let mut task = task.ok_or_else(|| CoreError::NotFound(id.to_string()))?;

        let mut header_stmt = conn
            .prepare("SELECT name, value FROM headers WHERE task_id = ?1")
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        let headers = header_stmt
            .query_map(params![id.to_string()], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        for header in headers {
            let (name, value) = header.map_err(|err| CoreError::Storage(err.to_string()))?;
            task.headers.insert(name, value);
        }

        let mut cookie_stmt = conn
            .prepare("SELECT name, value FROM cookies WHERE task_id = ?1")
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        let cookies = cookie_stmt
            .query_map(params![id.to_string()], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        for cookie in cookies {
            let (name, value) = cookie.map_err(|err| CoreError::Storage(err.to_string()))?;
            task.cookies.insert(name, value);
        }

        let mut mirror_stmt = conn
            .prepare("SELECT url FROM mirrors WHERE task_id = ?1 ORDER BY rank ASC")
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        let mirrors = mirror_stmt
            .query_map(params![id.to_string()], |row| Ok(row.get::<_, String>(0)?))
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        for mirror in mirrors {
            task.mirrors
                .push(mirror.map_err(|err| CoreError::Storage(err.to_string()))?);
        }

        Ok(task)
    }

    fn list_tasks(&self) -> CoreResult<Vec<Task>> {
        let conn = self.conn()?;
        let mut stmt = conn
            .prepare("SELECT id FROM tasks")
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        let ids = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(|err| CoreError::Storage(err.to_string()))?;

        let mut tasks = Vec::new();
        for id in ids {
            let id = id.map_err(|err| CoreError::Storage(err.to_string()))?;
            let task_id = TaskId::parse_str(&id).map_err(|_| CoreError::Storage(id))?;
            tasks.push(self.load_task(&task_id)?);
        }
        Ok(tasks)
    }

    fn delete_task(&mut self, id: &TaskId) -> CoreResult<()> {
        let mut conn = self.conn()?;
        let tx = conn
            .transaction()
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.execute("DELETE FROM tasks WHERE id = ?1", params![id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.execute("DELETE FROM headers WHERE task_id = ?1", params![id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.execute("DELETE FROM cookies WHERE task_id = ?1", params![id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.execute("DELETE FROM mirrors WHERE task_id = ?1", params![id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.execute("DELETE FROM segments WHERE task_id = ?1", params![id.to_string()])
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.commit()
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        Ok(())
    }

    fn save_segments(&mut self, task_id: &TaskId, segments: &[Segment]) -> CoreResult<()> {
        let mut conn = self.conn()?;
        let tx = conn
            .transaction()
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        tx.execute(
            "DELETE FROM segments WHERE task_id = ?1",
            params![task_id.to_string()],
        )
        .map_err(|err| CoreError::Storage(err.to_string()))?;
        for segment in segments {
            tx.execute(
                "
                INSERT INTO segments (task_id, segment_index, range_start, range_end, downloaded_bytes, status)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                ",
                params![
                    task_id.to_string(),
                    segment.index as i64,
                    segment.range_start as i64,
                    segment.range_end as i64,
                    segment.downloaded_bytes as i64,
                    segment.status.as_str(),
                ],
            )
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        }
        tx.commit()
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        Ok(())
    }

    fn load_segments(&self, task_id: &TaskId) -> CoreResult<Vec<Segment>> {
        let conn = self.conn()?;
        let mut stmt = conn
            .prepare(
                "
                SELECT segment_index, range_start, range_end, downloaded_bytes, status
                FROM segments WHERE task_id = ?1 ORDER BY segment_index ASC
                ",
            )
            .map_err(|err| CoreError::Storage(err.to_string()))?;
        let rows = stmt
            .query_map(params![task_id.to_string()], |row| {
                let status: String = row.get(4)?;
                let status = SegmentStatus::from_str(&status)
                    .ok_or_else(|| rusqlite::Error::InvalidQuery)?;
                Ok(Segment {
                    index: row.get::<_, i64>(0)? as u32,
                    range_start: row.get::<_, i64>(1)? as u64,
                    range_end: row.get::<_, i64>(2)? as u64,
                    downloaded_bytes: row.get::<_, i64>(3)? as u64,
                    status,
                })
            })
            .map_err(|err| CoreError::Storage(err.to_string()))?;

        let mut segments = Vec::new();
        for row in rows {
            segments.push(row.map_err(|err| CoreError::Storage(err.to_string()))?);
        }
        Ok(segments)
    }
}
