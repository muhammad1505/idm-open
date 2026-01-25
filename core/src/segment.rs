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

pub fn calculate_smart_concurrency(total_bytes: u64) -> u32 {
    match total_bytes {
        0..=20_971_520 => 1,             // < 20MB: 1 connection
        20_971_521..=209_715_200 => 4,   // 20MB - 200MB: 4 connections
        209_715_201..=2_147_483_648 => 8, // 200MB - 2GB: 8 connections
        _ => 16,                         // > 2GB: 16 connections
    }
}

pub fn build_segments(total_bytes: u64, max_segments: u32, min_segment_size: u64) -> Vec<Segment> {
    if total_bytes == 0 {
        return vec![Segment::new(0, 0, 0)];
    }

    // 1. Determine smart concurrency based on file size
    let smart_count = calculate_smart_concurrency(total_bytes);

    // 2. Clamp by user configuration (max_segments)
    let mut target_count = if smart_count > max_segments {
        max_segments
    } else {
        smart_count
    };

    // 3. Ensure we don't violate min_segment_size (unless it forces 1 segment)
    if min_segment_size > 0 {
        let max_possible_by_size = total_bytes / min_segment_size;
        if max_possible_by_size < target_count as u64 {
            target_count = max_possible_by_size as u32;
        }
    }

    // Always at least 1 segment
    if target_count < 1 {
        target_count = 1;
    }

    let segment_count = target_count as u64;
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
        // Distribute remainder bytes to the first few segments
        if index < remainder {
            end += 1;
        }
        segments.push(Segment::new(index as u32, start, end));
        start = end + 1;
    }

    segments
}
