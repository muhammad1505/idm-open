use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::task::TaskId;

#[derive(Debug, Clone)]
pub struct QueueItem {
    pub id: TaskId,
    pub priority: i32,
    pub inserted_at: u64,
}

impl QueueItem {
    pub fn new(id: TaskId, priority: i32) -> Self {
        Self {
            id,
            priority,
            inserted_at: now_epoch(),
        }
    }
}

impl Eq for QueueItem {}

impl PartialEq for QueueItem {
    fn eq(&self, other: &Self) -> bool {
        self.priority == other.priority && self.inserted_at == other.inserted_at && self.id == other.id
    }
}

impl Ord for QueueItem {
    fn cmp(&self, other: &Self) -> Ordering {
        self.priority
            .cmp(&other.priority)
            .then_with(|| other.inserted_at.cmp(&self.inserted_at))
            .then_with(|| self.id.as_u128().cmp(&other.id.as_u128()))
    }
}

impl PartialOrd for QueueItem {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

#[derive(Debug, Default)]
pub struct TaskQueue {
    heap: BinaryHeap<QueueItem>,
}

impl TaskQueue {
    pub fn push(&mut self, item: QueueItem) {
        self.heap.push(item);
    }

    pub fn pop(&mut self) -> Option<QueueItem> {
        self.heap.pop()
    }

    pub fn len(&self) -> usize {
        self.heap.len()
    }

    pub fn is_empty(&self) -> bool {
        self.heap.is_empty()
    }
}

fn now_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}
