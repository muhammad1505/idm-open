use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SegmentStatus {
    Pending,
    Active,
    Completed,
    Failed,
}

impl SegmentStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            SegmentStatus::Pending => "pending",
            SegmentStatus::Active => "active",
            SegmentStatus::Completed => "completed",
            SegmentStatus::Failed => "failed",
        }
    }

    pub fn from_str(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(SegmentStatus::Pending),
            "active" => Some(SegmentStatus::Active),
            "completed" => Some(SegmentStatus::Completed),
            "failed" => Some(SegmentStatus::Failed),
            _ => None,
        }
    }
}

impl fmt::Display for SegmentStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    pub index: u32,
    pub range_start: u64,
    pub range_end: u64,
    pub downloaded_bytes: u64,
    pub status: SegmentStatus,
}

impl Segment {
    pub fn new(index: u32, range_start: u64, range_end: u64) -> Self {
        Self {
            index,
            range_start,
            range_end,
            downloaded_bytes: 0,
            status: SegmentStatus::Pending,
        }
    }

    pub fn size(&self) -> u64 {
        if self.range_end >= self.range_start {
            self.range_end - self.range_start + 1
        } else {
            0
        }
    }
}

pub fn build_segments(total_bytes: u64, max_segments: u32, min_segment_size: u64) -> Vec<Segment> {
    if total_bytes == 0 {
        return vec![Segment::new(0, 0, 0)];
    }

    if max_segments <= 1 || total_bytes <= min_segment_size {
        return vec![Segment::new(0, 0, total_bytes - 1)];
    }

    let mut segment_count = (total_bytes + min_segment_size - 1) / min_segment_size;
    if segment_count == 0 {
        segment_count = 1;
    }
    if segment_count > max_segments as u64 {
        segment_count = max_segments as u64;
    }

    let base = total_bytes / segment_count;
    let remainder = total_bytes % segment_count;

    let mut segments = Vec::with_capacity(segment_count as usize);
    let mut start = 0u64;
    for index in 0..segment_count {
        let mut end = if index == segment_count - 1 {
            total_bytes - 1
        } else {
            start + base - 1
        };
        if index < remainder {
            end += 1;
        }
        segments.push(Segment::new(index as u32, start, end));
        start = end + 1;
    }

    segments
}
