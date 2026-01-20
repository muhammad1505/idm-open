# Architecture

## Overview
The project is split into a performance-focused Rust core and a Flutter UI. Platform integrations (desktop browser extensions and Android share/intent flow) communicate with the core through an FFI layer or a local host.

## Core engine (Rust)
Key modules:
- engine: Orchestrates queue, task state, and download workers
- task: Task model, status, metadata
- segment: Segment model and per-task segmentation strategy
- net: HTTP/HTTPS/FTP client, headers, cookies, auth
- storage: Persistence (SQLite), crash recovery, history
- scheduler: Time-based scheduling and priority queue
- throttle: Speed limiter (global and per-task)
- checksum: Verification (MD5/SHA)

## Data flow
1) UI or integration submits a URL + metadata to core
2) Core creates a Task and persists it
3) Scheduler pulls tasks into active slots
4) Segmenter creates range segments
5) Net client downloads segments; storage updates progress
6) On completion, checksum runs and state updates

## FFI boundary
The core exposes a stable C ABI for use by Flutter and desktop native messaging hosts. The ABI handles:
- Create engine instance
- Add/pause/resume/cancel tasks
- Query task list/status
- Subscribe to events (poll or callback)

## Desktop browser integration
- Browser extension captures download events
- Extension sends a message to native host
- Native host calls core-ffi to enqueue the download

## Android integration
- Share/intent action to send URL to app
- Optional intent filter for http/https (user-chosen handler)
- App calls core-ffi to enqueue

## Non-goals
- iOS and macOS support
- DRM or proprietary download integrations
