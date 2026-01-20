# Roadmap

## Phase 1: Core scaffolding
- Data model, status/state machine
- Engine API surface
- CLI to create/pause/resume tasks

## Phase 2: Single-stream download
- HTTP download with resume
- Basic persistence and recovery
- Throttle (global)

## Phase 3: Segmented download
- Dynamic range segmentation
- Per-task throttling
- Retry with backoff

## Phase 4: Scheduler + queue
- Priority queue
- Time-based scheduling
- Idle/active slot management

## Phase 5: Reliability + verification
- Checksum verification
- Mirror URL fallback
- Proxy and auth support

## Phase 6: Platform integration
- Desktop browser extension + native host
- Android share/intent integration
- Flutter UI
