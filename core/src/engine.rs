use std::collections::HashSet;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU64, AtomicU8, Ordering};
use std::thread;
use std::thread::JoinHandle;
use std::time::Duration;

use crate::checksum::verify_checksum;
use crate::config::EngineConfig;
use crate::error::{CoreError, CoreResult};
use crate::net::{DownloadRequest, NetClient, ReqwestNetClient};
use crate::queue::{QueueItem, TaskQueue};
use crate::resolver::{
    detect_provider, is_html_content_type, resolve_html_download, resolve_url_candidates, Provider,
};
use crate::scheduler::Scheduler;
use crate::segment::{build_segments, Segment, SegmentStatus};
use crate::storage::{MemoryStorage, Storage};
use crate::task::{Task, TaskId, TaskStatus};
use crate::throttle::Throttle;
use reqwest::Url;

const STOP_NONE: u8 = 0;
const STOP_PAUSED: u8 = 1;
const STOP_CANCELED: u8 = 2;
const STOP_FAILED: u8 = 3;

pub struct DownloadEngine {
    pub config: EngineConfig,
    pub scheduler: Scheduler,
    storage: Arc<Mutex<Box<dyn Storage>>>,
    net: Arc<dyn NetClient>,
    queue: Mutex<TaskQueue>,
    active: Arc<Mutex<HashSet<TaskId>>>,
    handles: Mutex<Vec<JoinHandle<()>>>,
}

impl DownloadEngine {
    pub fn new(config: EngineConfig) -> Self {
        let scheduler = Scheduler::new(config.max_concurrent_tasks);
        let net = ReqwestNetClient::new(&config.user_agent)
            .unwrap_or_else(|_| ReqwestNetClient::new("IDM-Open/0.1").expect("net client"));
        Self {
            config,
            scheduler,
            storage: Arc::new(Mutex::new(Box::new(MemoryStorage::default()))),
            net: Arc::new(net),
            queue: Mutex::new(TaskQueue::default()),
            active: Arc::new(Mutex::new(HashSet::new())),
            handles: Mutex::new(Vec::new()),
        }
    }

    pub fn with_storage(mut self, storage: Box<dyn Storage>) -> Self {
        self.storage = Arc::new(Mutex::new(storage));
        self
    }

    pub fn with_net_client(mut self, net: Box<dyn NetClient>) -> Self {
        self.net = Arc::from(net);
        self
    }

    pub fn add_task(&self, url: String, dest_path: String) -> CoreResult<TaskId> {
        let task = Task::new(url, dest_path);
        let id = task.id;
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.save_task(&task)?;
        self.queue
            .lock()
            .map_err(|_| CoreError::Storage("queue lock poisoned".to_string()))?
            .push(QueueItem::new(id, task.priority));
        Ok(id)
    }

    pub fn list_tasks(&self) -> CoreResult<Vec<Task>> {
        let storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.list_tasks()
    }

    pub fn enqueue_queued(&self) -> CoreResult<usize> {
        let tasks = self.list_tasks()?;
        let mut queued = 0usize;
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let mut queue = self
            .queue
            .lock()
            .map_err(|_| CoreError::Storage("queue lock poisoned".to_string()))?;

        for mut task in tasks {
            let needs_queue = match task.status {
                TaskStatus::Queued => true,
                TaskStatus::Active => {
                    task.status = TaskStatus::Queued;
                    task.touch();
                    storage.save_task(&task)?;
                    true
                }
                _ => false,
            };
            if needs_queue {
                queue.push(QueueItem::new(task.id, task.priority));
                queued += 1;
            }
        }
        Ok(queued)
    }

    pub fn get_task(&self, id: &TaskId) -> CoreResult<Task> {
        let storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.load_task(id)
    }

    pub fn pause_task(&self, id: &TaskId) -> CoreResult<()> {
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let mut task = storage.load_task(id)?;
        if task.status != TaskStatus::Active {
            return Err(CoreError::InvalidState(format!(
                "cannot pause task in state {}",
                task.status
            )));
        }
        task.status = TaskStatus::Paused;
        task.touch();
        storage.save_task(&task)?;
        if let Ok(mut active) = self.active.lock() {
            active.remove(id);
        }
        Ok(())
    }

    pub fn resume_task(&self, id: &TaskId) -> CoreResult<()> {
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let mut task = storage.load_task(id)?;
        if task.status != TaskStatus::Paused && task.status != TaskStatus::Failed {
            return Err(CoreError::InvalidState(format!(
                "cannot resume task in state {}",
                task.status
            )));
        }
        task.status = TaskStatus::Queued;
        task.touch();
        storage.save_task(&task)?;
        self.queue
            .lock()
            .map_err(|_| CoreError::Storage("queue lock poisoned".to_string()))?
            .push(QueueItem::new(task.id, task.priority));
        Ok(())
    }

    pub fn cancel_task(&self, id: &TaskId) -> CoreResult<()> {
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let mut task = storage.load_task(id)?;
        task.status = TaskStatus::Canceled;
        task.touch();
        storage.save_task(&task)?;
        if let Ok(mut active) = self.active.lock() {
            active.remove(id);
        }
        Ok(())
    }

    pub fn remove_task(&self, id: &TaskId) -> CoreResult<()> {
        if let Ok(active) = self.active.lock() {
            if active.contains(id) {
                return Err(CoreError::InvalidState(format!(
                    "cannot remove active task {}",
                    id
                )));
            }
        }
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.delete_task(id)?;
        Ok(())
    }

    pub fn start_next(&self) -> CoreResult<Option<TaskId>> {
        let active_count = self
            .active
            .lock()
            .map_err(|_| CoreError::Storage("active lock poisoned".to_string()))?
            .len();
        if !self.scheduler.can_start(active_count) {
            return Ok(None);
        }
        let item = self
            .queue
            .lock()
            .map_err(|_| CoreError::Storage("queue lock poisoned".to_string()))?
            .pop();
        let Some(item) = item else {
            return Ok(None);
        };

        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let mut task = match storage.load_task(&item.id) {
            Ok(t) => t,
            Err(CoreError::NotFound(_)) => return self.start_next(),
            Err(e) => return Err(e),
        };
        if task.status != TaskStatus::Queued {
            return Ok(None);
        }
        task.status = TaskStatus::Active;
        task.error = None;
        task.touch();
        storage.save_task(&task)?;

        if let Ok(mut active) = self.active.lock() {
            active.insert(task.id);
        }

        let task_id = task.id;
        let storage = Arc::clone(&self.storage);
        let net = Arc::clone(&self.net);
        let config = self.config.clone();
        let active = Arc::clone(&self.active);
        let handle = thread::spawn(move || {
            let outcome = download_task(task_id, config, storage.clone(), net);
            let (status, error) = match outcome {
                Ok(status) => (status, None),
                Err(err) => (TaskStatus::Failed, Some(err.to_string())),
            };

            if let Ok(mut storage) = storage.lock() {
                if let Ok(mut task) = storage.load_task(&task_id) {
                    task.status = status;
                    if let Some(error) = error {
                        task.error = Some(error);
                    }
                    task.touch();
                    let _ = storage.save_task(&task);
                }
            }

            if let Ok(mut active) = active.lock() {
                active.remove(&task_id);
            }
        });

        self.handles
            .lock()
            .map_err(|_| CoreError::Storage("handle lock poisoned".to_string()))?
            .push(handle);

        Ok(Some(task_id))
    }

    pub fn run(&self) -> CoreResult<()> {
        loop {
            while self.start_next()?.is_some() {}
            self.reap_handles();
            let queue_empty = self
                .queue
                .lock()
                .map_err(|_| CoreError::Storage("queue lock poisoned".to_string()))?
                .is_empty();
            let active_empty = self
                .active
                .lock()
                .map_err(|_| CoreError::Storage("active lock poisoned".to_string()))?
                .is_empty();
            if queue_empty && active_empty {
                break;
            }
            thread::sleep(Duration::from_millis(200));
        }
        self.wait_all();
        Ok(())
    }

    pub fn wait_all(&self) {
        if let Ok(mut handles) = self.handles.lock() {
            for handle in handles.drain(..) {
                let _ = handle.join();
            }
        }
    }

    fn reap_handles(&self) {
        if let Ok(mut handles) = self.handles.lock() {
            let mut index = 0usize;
            while index < handles.len() {
                if handles[index].is_finished() {
                    let handle = handles.remove(index);
                    let _ = handle.join();
                } else {
                    index += 1;
                }
            }
        }
    }
}

struct ProgressTracker {
    task_id: TaskId,
    storage: Arc<Mutex<Box<dyn Storage>>>,
    segments: Arc<Mutex<Vec<Segment>>>,
    downloaded: AtomicU64,
    last_flush: AtomicU64,
    last_status_check: AtomicU64,
    flush_bytes: u64,
    status_check_bytes: u64,
}

impl ProgressTracker {
    fn new(
        task_id: TaskId,
        storage: Arc<Mutex<Box<dyn Storage>>>,
        segments: Arc<Mutex<Vec<Segment>>>,
        downloaded: u64,
        flush_bytes: u64,
        status_check_bytes: u64,
    ) -> Self {
        Self {
            task_id,
            storage,
            segments,
            downloaded: AtomicU64::new(downloaded),
            last_flush: AtomicU64::new(downloaded),
            last_status_check: AtomicU64::new(downloaded),
            flush_bytes,
            status_check_bytes,
        }
    }

    fn add_bytes(&self, index: usize, bytes: u64) -> CoreResult<()> {
        if let Ok(mut segments) = self.segments.lock() {
            if let Some(segment) = segments.get_mut(index) {
                let new_value = segment.downloaded_bytes.saturating_add(bytes);
                if segment.size() > 0 {
                    segment.downloaded_bytes = new_value.min(segment.size());
                } else {
                    segment.downloaded_bytes = new_value;
                }
            }
        }
        let total = self.downloaded.fetch_add(bytes, Ordering::Relaxed) + bytes;
        self.maybe_flush(total)?;
        Ok(())
    }

    fn maybe_flush(&self, total: u64) -> CoreResult<()> {
        let last = self.last_flush.load(Ordering::Relaxed);
        if total.saturating_sub(last) >= self.flush_bytes {
            if self
                .last_flush
                .compare_exchange(last, total, Ordering::SeqCst, Ordering::Relaxed)
                .is_ok()
            {
                self.flush(total)?;
            }
        }
        Ok(())
    }

    fn flush(&self, total: u64) -> CoreResult<()> {
        let mut storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let mut task = storage.load_task(&self.task_id)?;
        task.downloaded_bytes = total;
        task.touch();
        storage.save_task(&task)?;
        let segments = self
            .segments
            .lock()
            .map_err(|_| CoreError::Storage("segment lock poisoned".to_string()))?;
        storage.save_segments(&self.task_id, &segments)?;
        Ok(())
    }

    fn maybe_check_status(&self, stop_flag: &AtomicU8) -> CoreResult<()> {
        let total = self.downloaded.load(Ordering::Relaxed);
        let last = self.last_status_check.load(Ordering::Relaxed);
        if total.saturating_sub(last) < self.status_check_bytes {
            return Ok(());
        }
        if self
            .last_status_check
            .compare_exchange(last, total, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return Ok(());
        }
        let storage = self
            .storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        if let Ok(task) = storage.load_task(&self.task_id) {
            match task.status {
                TaskStatus::Paused => {
                    stop_flag.store(STOP_PAUSED, Ordering::SeqCst);
                }
                TaskStatus::Canceled => {
                    stop_flag.store(STOP_CANCELED, Ordering::SeqCst);
                }
                _ => {}
            }
        }
        Ok(())
    }
}

use crate::hls::HlsDownloader;

// ... imports ...

fn download_task(
    task_id: TaskId,
    config: EngineConfig,
    storage: Arc<Mutex<Box<dyn Storage>>>,
    net: Arc<dyn NetClient>,
) -> CoreResult<TaskStatus> {
    let mut task = {
        let storage = storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.load_task(&task_id)?
    };

    // --- HLS CHECK ---
    if task.url.contains(".m3u8") {
        let stop_flag = Arc::new(AtomicU8::new(STOP_NONE));
        let storage_clone = storage.clone();
        let tid = task_id;
        
        let status = HlsDownloader::download(
            &mut task,
            net,
            stop_flag,
            move |bytes| {
                 if let Ok(mut s) = storage_clone.lock() {
                     if let Ok(mut t) = s.load_task(&tid) {
                         t.downloaded_bytes = bytes;
                         // Hack: Update total bytes dynamically for HLS as we go
                         if t.total_bytes < bytes { t.total_bytes = bytes; } 
                         let _ = s.save_task(&t);
                     }
                 }
            }
        )?;
        return Ok(status);
    }
    // --- END HLS CHECK ---

    let url_candidates = resolve_url_candidates(task.url_candidates());
    let mut total_bytes = task.total_bytes;
    let mut accept_ranges = false;
    let mut selected_url: Option<String> = None;
    let mut selected_head = None;
    let mut resolved_candidates = Vec::new();

    for url in &url_candidates {
        let mut head_req = DownloadRequest::new(url.clone(), config.user_agent.clone());
        head_req.headers = task.headers.clone();
        head_req.cookies = task.cookies.clone();
        head_req.proxy = task.proxy_url.clone();
        if let (Some(user), Some(pass)) = (task.auth_user.clone(), task.auth_pass.clone()) {
            head_req.basic_auth = Some((user, pass));
        }

        if let Ok(resp) = net.head(&head_req) {
            if resp.status_code >= 200 && resp.status_code < 400 {
                if is_html_content_type(resp.content_type.as_deref()) {
                    let provider = detect_provider(url);
                    if provider == Provider::Mega {
                        return Err(CoreError::Unsupported(
                            "mega.nz requires Mega SDK integration".to_string(),
                        ));
                    }
                    let resolved = resolve_html_download(net.as_ref(), &head_req)?;
                    for resolved_url in resolved {
                        resolved_candidates.push(resolved_url.clone());
                        let mut resolved_req =
                            DownloadRequest::new(resolved_url.clone(), config.user_agent.clone());
                        resolved_req.headers = task.headers.clone();
                        resolved_req.cookies = task.cookies.clone();
                        resolved_req.proxy = task.proxy_url.clone();
                        if let (Some(user), Some(pass)) =
                            (task.auth_user.clone(), task.auth_pass.clone())
                        {
                            resolved_req.basic_auth = Some((user, pass));
                        }

                        if let Ok(resolved_resp) = net.head(&resolved_req) {
                            if resolved_resp.status_code >= 200
                                && resolved_resp.status_code < 400
                                && !is_html_content_type(resolved_resp.content_type.as_deref())
                            {
                                selected_url = Some(resolved_url.clone());
                                total_bytes = resolved_resp.total_bytes.unwrap_or(total_bytes);
                                accept_ranges = resolved_resp.accept_ranges;
                                selected_head = Some(resolved_resp);
                                break;
                            }
                        }
                    }
                    if selected_url.is_some() {
                        break;
                    }
                    if provider != Provider::Unknown {
                        continue;
                    }
                    selected_url = Some(url.clone());
                    total_bytes = resp.total_bytes.unwrap_or(total_bytes);
                    accept_ranges = resp.accept_ranges;
                    break;
                } else {
                    selected_url = Some(url.clone());
                    total_bytes = resp.total_bytes.unwrap_or(total_bytes);
                    accept_ranges = resp.accept_ranges;
                    selected_head = Some(resp);
                    break;
                }
            }
        }
    }

    let selected_url = selected_url.ok_or_else(|| {
        CoreError::Network("no reachable download URL after resolution".to_string())
    })?;
    let content_disposition = selected_head
        .as_ref()
        .and_then(|resp| resp.content_disposition.as_deref());
    let resolved_dest = resolve_dest_path(&task.dest_path, &selected_url, content_disposition);
    if resolved_dest != task.dest_path {
        task.dest_path = resolved_dest;
    }
    let mut download_urls = Vec::new();
    let mut seen = HashSet::new();
    if seen.insert(selected_url.clone()) {
        download_urls.push(selected_url);
    }
    for url in resolved_candidates {
        if seen.insert(url.clone()) {
            download_urls.push(url);
        }
    }
    for url in url_candidates {
        if seen.insert(url.clone()) {
            download_urls.push(url);
        }
    }

    let use_ranges = accept_ranges && total_bytes > 0 && config.max_segments_per_task > 1;
    let mut segments = {
        let storage = storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.load_segments(&task_id)?
    };

    let rebuild_segments = segments.is_empty()
        || (!use_ranges && segments.len() > 1)
        || (total_bytes > 0
            && segments
                .iter()
                .map(|seg| seg.range_end)
                .max()
                .map(|end| end != total_bytes.saturating_sub(1))
                .unwrap_or(true));

    if rebuild_segments {
        segments = if use_ranges {
            build_segments(total_bytes, config.max_segments_per_task, config.min_segment_size_bytes)
        } else {
            if total_bytes > 0 {
                vec![Segment::new(0, 0, total_bytes - 1)]
            } else {
                vec![Segment::new(0, 0, 0)]
            }
        };
    }

    for segment in &mut segments {
        if segment.status == SegmentStatus::Active {
            segment.status = SegmentStatus::Pending;
        }
        if total_bytes > 0 && segment.downloaded_bytes >= segment.size() {
            segment.downloaded_bytes = segment.size();
            segment.status = SegmentStatus::Completed;
        }
    }

    let downloaded_total: u64 = segments.iter().map(|seg| seg.downloaded_bytes).sum();
    task.total_bytes = total_bytes;
    task.downloaded_bytes = downloaded_total;
    task.error = None;
    task.touch();

    {
        let mut storage = storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        storage.save_task(&task)?;
        storage.save_segments(&task.id, &segments)?;
    }

    if let Some(parent) = Path::new(&task.dest_path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)
                .map_err(|err| CoreError::Io(err.to_string()))?;
        }
    }

    if total_bytes > 0 {
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .open(&task.dest_path)
            .map_err(|err| CoreError::Io(err.to_string()))?;
        file.set_len(total_bytes)
            .map_err(|err| CoreError::Io(err.to_string()))?;
    }

    let segments_shared = Arc::new(Mutex::new(segments));
    let progress = Arc::new(ProgressTracker::new(
        task_id,
        Arc::clone(&storage),
        Arc::clone(&segments_shared),
        downloaded_total,
        config.progress_flush_bytes,
        config.status_check_bytes,
    ));

    let throttle = Throttle::new(
        config.global_speed_limit_bytes_per_sec,
        config.per_task_speed_limit_bytes_per_sec,
    );

    let stop_flag = Arc::new(AtomicU8::new(STOP_NONE));
    let errors: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));

    let mut handles = Vec::new();
    let mut segments_to_download = Vec::new();
    if let Ok(mut segments) = segments_shared.lock() {
        for (index, segment) in segments.iter_mut().enumerate() {
            if segment.status != SegmentStatus::Completed {
                segment.status = SegmentStatus::Active;
                segments_to_download.push(index);
            }
        }
    }

    {
        let mut storage = storage
            .lock()
            .map_err(|_| CoreError::Storage("storage lock poisoned".to_string()))?;
        let segments = segments_shared
            .lock()
            .map_err(|_| CoreError::Storage("segment lock poisoned".to_string()))?;
        storage.save_segments(&task_id, &segments)?;
    }

    for index in segments_to_download {
        let net = Arc::clone(&net);
        let storage = Arc::clone(&storage);
        let segments = Arc::clone(&segments_shared);
        let progress = Arc::clone(&progress);
        let throttle = throttle.clone();
        let stop_flag = Arc::clone(&stop_flag);
        let errors = Arc::clone(&errors);
        let task_clone = task.clone();
        let url_candidates = download_urls.clone();
        let config = config.clone();

        let handle = thread::spawn(move || {
            let result = download_segment(
                index,
                &task_clone,
                &url_candidates,
                &config,
                net,
                storage,
                segments,
                progress,
                throttle,
                stop_flag.clone(),
            );
            if let Err(err) = result {
                stop_flag.store(STOP_FAILED, Ordering::SeqCst);
                if let Ok(mut errors) = errors.lock() {
                    errors.push(err.to_string());
                }
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        let _ = handle.join();
    }

    let total_downloaded = progress.downloaded.load(Ordering::Relaxed);
    progress.flush(total_downloaded)?;

    match stop_flag.load(Ordering::SeqCst) {
        STOP_PAUSED => return Ok(TaskStatus::Paused),
        STOP_CANCELED => return Ok(TaskStatus::Canceled),
        STOP_FAILED => {
            if let Ok(mut storage) = storage.lock() {
                if let Ok(mut task) = storage.load_task(&task_id) {
                    if let Ok(errors) = errors.lock() {
                        if !errors.is_empty() {
                            task.error = Some(errors.join("; "));
                        }
                    }
                    let _ = storage.save_task(&task);
                }
            }
            return Ok(TaskStatus::Failed);
        }
        _ => {}
    }

    if total_bytes == 0 {
        if let Ok(meta) = fs::metadata(&task.dest_path) {
            total_bytes = meta.len();
            if let Ok(mut storage) = storage.lock() {
                if let Ok(mut task) = storage.load_task(&task_id) {
                    task.total_bytes = total_bytes;
                    let _ = storage.save_task(&task);
                }
            }
        }
    }

    if let Some(checksum) = &task.checksum {
        if !verify_checksum(&task.dest_path, checksum) {
            if let Ok(mut storage) = storage.lock() {
                if let Ok(mut task) = storage.load_task(&task_id) {
                    task.error = Some("checksum mismatch".to_string());
                    let _ = storage.save_task(&task);
                }
            }
            return Ok(TaskStatus::Failed);
        }
    }

    Ok(TaskStatus::Completed)
}

fn download_segment(
    index: usize,
    task: &Task,
    url_candidates: &[String],
    config: &EngineConfig,
    net: Arc<dyn NetClient>,
    storage: Arc<Mutex<Box<dyn Storage>>>,
    segments: Arc<Mutex<Vec<Segment>>>,
    progress: Arc<ProgressTracker>,
    throttle: Throttle,
    stop_flag: Arc<AtomicU8>,
) -> CoreResult<()> {
    let (range_start, range_end, use_ranges) = {
        let segments = segments
            .lock()
            .map_err(|_| CoreError::Storage("segment lock poisoned".to_string()))?;
        let segment = segments
            .get(index)
            .ok_or_else(|| CoreError::NotFound("segment".to_string()))?;
        let use_ranges = task.total_bytes > 0 && segment.size() > 0;
        (segment.range_start, segment.range_end, use_ranges)
    };

    let mut last_error: Option<CoreError> = None;
    let backoff = Duration::from_secs(config.retry_backoff_secs);

    for attempt in 0..=config.retry_count {
        if stop_flag.load(Ordering::SeqCst) != STOP_NONE {
            return Ok(());
        }
        for url in url_candidates {
            if stop_flag.load(Ordering::SeqCst) != STOP_NONE {
                return Ok(());
            }
            let current_downloaded = {
                let segments = segments
                    .lock()
                    .map_err(|_| CoreError::Storage("segment lock poisoned".to_string()))?;
                segments
                    .get(index)
                    .map(|segment| segment.downloaded_bytes)
                    .unwrap_or(0)
            };

            if use_ranges && current_downloaded >= (range_end - range_start + 1) {
                return Ok(());
            }

            let start = if use_ranges {
                range_start.saturating_add(current_downloaded)
            } else {
                0
            };
            let end = if use_ranges { range_end } else { 0 };

            let mut req = DownloadRequest::new(url.clone(), config.user_agent.clone());
            req.headers = task.headers.clone();
            req.cookies = task.cookies.clone();
            req.proxy = task.proxy_url.clone();
            if let (Some(user), Some(pass)) = (task.auth_user.clone(), task.auth_pass.clone()) {
                req.basic_auth = Some((user, pass));
            }
            if use_ranges {
                req.range = Some((start, end));
            }

            let response = match net.get_stream(&req) {
                Ok(resp) => resp,
                Err(err) => {
                    last_error = Some(err);
                    continue;
                }
            };

            let status = response.status();
            if use_ranges && status.as_u16() != 206 {
                last_error = Some(CoreError::Network(format!(
                    "range not supported (status {})",
                    status.as_u16()
                )));
                continue;
            }
            if !status.is_success() {
                last_error = Some(CoreError::Network(format!(
                    "download failed with status {}",
                    status.as_u16()
                )));
                continue;
            }

            if let Err(err) = stream_to_file(
                response,
                &task.dest_path,
                start,
                progress.clone(),
                index,
                throttle.clone(),
                stop_flag.clone(),
            ) {
                last_error = Some(err);
                continue;
            }

            if stop_flag.load(Ordering::SeqCst) != STOP_NONE {
                return Ok(());
            }

            if let Ok(mut segments) = segments.lock() {
                if let Some(segment) = segments.get_mut(index) {
                    segment.status = SegmentStatus::Completed;
                }
            }
            if let Ok(mut storage) = storage.lock() {
                if let Ok(segments) = segments.lock() {
                    let _ = storage.save_segments(&task.id, &segments);
                }
            }
            return Ok(());
        }

        if attempt < config.retry_count {
            thread::sleep(backoff);
        }
    }

    Err(last_error.unwrap_or_else(|| {
        CoreError::Network(format!("failed to download segment {}", index))
    }))
}

fn stream_to_file(
    mut response: reqwest::blocking::Response,
    dest_path: &str,
    start_offset: u64,
    progress: Arc<ProgressTracker>,
    segment_index: usize,
    throttle: Throttle,
    stop_flag: Arc<AtomicU8>,
) -> CoreResult<()> {
    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .open(dest_path)
        .map_err(|err| CoreError::Io(err.to_string()))?;
    file.seek(SeekFrom::Start(start_offset))
        .map_err(|err| CoreError::Io(err.to_string()))?;

    let mut buffer = vec![0u8; 1024 * 64];
    loop {
        if stop_flag.load(Ordering::SeqCst) != STOP_NONE {
            return Ok(());
        }
        let read = response
            .read(&mut buffer)
            .map_err(|err| CoreError::Network(err.to_string()))?;
        if read == 0 {
            break;
        }
        file.write_all(&buffer[..read])
            .map_err(|err| CoreError::Io(err.to_string()))?;
        progress.add_bytes(segment_index, read as u64)?;
        progress.maybe_check_status(&stop_flag)?;
        throttle.throttle(read as u64);
    }

    Ok(())
}

fn resolve_dest_path(dest_path: &str, url: &str, content_disposition: Option<&str>) -> String {
    let dest_path = dest_path.trim();
    let is_empty = dest_path.is_empty();
    let mut path = PathBuf::from(dest_path);

    let mut treat_as_dir = is_empty
        || dest_path.ends_with('/')
        || dest_path.ends_with('\\')
        || path.is_dir();

    if is_empty {
        path = default_download_dir();
        treat_as_dir = true;
    }

    if treat_as_dir {
        let filename = filename_from_content_disposition(content_disposition)
            .or_else(|| filename_from_url(url))
            .unwrap_or_else(|| "download.bin".to_string());
        let filename = sanitize_filename(&filename);
        return path.join(filename).to_string_lossy().to_string();
    }

    dest_path.to_string()
}

fn default_download_dir() -> PathBuf {
    if let Ok(dir) = env::var("IDM_DOWNLOAD_DIR") {
        return PathBuf::from(dir);
    }
    let shared = Path::new("/storage/emulated/0/Download");
    if shared.exists() {
        return shared.to_path_buf();
    }
    let sdcard = Path::new("/sdcard/Download");
    if sdcard.exists() {
        return sdcard.to_path_buf();
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

fn filename_from_content_disposition(value: Option<&str>) -> Option<String> {
    let value = value?;
    let mut filename_star: Option<String> = None;
    let mut filename: Option<String> = None;

    for part in value.split(';') {
        let part = part.trim();
        if part.to_ascii_lowercase().starts_with("filename*=") {
            let raw = part.splitn(2, '=').nth(1)?.trim().trim_matches('"');
            let decoded = if let Some(idx) = raw.find("''") {
                percent_decode_ascii(&raw[idx + 2..])
            } else {
                percent_decode_ascii(raw)
            };
            if !decoded.is_empty() {
                filename_star = Some(decoded);
            }
        } else if part.to_ascii_lowercase().starts_with("filename=") {
            let raw = part.splitn(2, '=').nth(1)?.trim().trim_matches('"');
            if !raw.is_empty() {
                filename = Some(raw.to_string());
            }
        }
    }

    filename_star.or(filename)
}

fn filename_from_url(url: &str) -> Option<String> {
    let parsed = Url::parse(url).ok()?;
    let path = parsed.path();
    let name = path.rsplit('/').next().unwrap_or("");
    if name.is_empty() {
        None
    } else {
        let mut decoded = percent_decode_ascii(name);
        if decoded.contains('+') {
            decoded = decoded.replace('+', " ");
        }
        Some(decoded)
    }
}

fn percent_decode_ascii(value: &str) -> String {
    let mut out = String::new();
    let bytes = value.as_bytes();
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let hi = bytes[index + 1];
            let lo = bytes[index + 2];
            if let (Some(hi), Some(lo)) = (hex_value(hi), hex_value(lo)) {
                let decoded = (hi << 4) | lo;
                if decoded.is_ascii() && decoded >= 0x20 && decoded != b'/' && decoded != b'\\' {
                    out.push(decoded as char);
                } else {
                    out.push('_');
                }
                index += 3;
                continue;
            }
        }
        let ch = bytes[index];
        if ch.is_ascii() && ch != b'/' && ch != b'\\' {
            out.push(ch as char);
        } else {
            out.push('_');
        }
        index += 1;
    }
    out
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn sanitize_filename(name: &str) -> String {
    let mut out = String::new();
    let mut last_was_sep = false;
    for ch in name.chars() {
        let normalized = match ch {
            '+' => ' ',
            _ => ch,
        };
        let allowed = normalized.is_ascii_alphanumeric()
            || matches!(normalized, '.' | '_' | '-' | ' ' | '(' | ')' | '[' | ']');
        let mapped = if allowed { normalized } else { '_' };
        if mapped == '_' || mapped == ' ' {
            if last_was_sep {
                continue;
            }
            last_was_sep = true;
            out.push(mapped);
        } else {
            last_was_sep = false;
            out.push(mapped);
        }
    }
    let trimmed = out.trim_matches(&[' ', '.', '_'][..]).trim();
    if trimmed.is_empty() {
        "download.bin".to_string()
    } else {
        trimmed.to_string()
    }
}
