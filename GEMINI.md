# Smart Download Manager (SDM) - Project Overview

**Identity:** "Fast. Resumable. Everywhere."
**Previous Name:** IDM-Open / idm-open

This document provides context for the **Smart Download Manager (SDM)** project, an open-source, cross-platform download manager designed for Android, Windows, and Linux. It aims to replicate the robustness of IDM with a modern codebase.

## Project Vision & Goal

**Goal:** Create a superior download manager that offers high speed, stability, resume capability, multi-connection support, and advanced scheduling, all within a unified cross-platform codebase.

**Key Features (SDM):**
*   **Robust Engine:** Multi-part (segmented) downloading, retry logic, resume capability, and checksum verification.
*   **Cross-Platform UI:** Consistent Flutter-based interface for Android, Windows, and Linux.
*   **Browser Integration:** "Download with SDM" via extensions (Chrome/Edge/Firefox) and Native Messaging.
*   **Management:** Queue management and advanced scheduler.
*   **Media Grabber:** (Future) Video/audio detection from web pages.

## Technical Architecture

The project follows a layered architecture (Option A: Flutter + Rust):

1.  **Core Engine (`core/`):** The heavy lifter written in **Rust**. Handles networking, file I/O, SQLite database, and download logic (segmentation, resume).
2.  **FFI Layer (`core-ffi/`):** Exposes the Rust core to Flutter via `flutter_rust_bridge`.
3.  **UI (`ui/`):** A **Flutter** application providing the user interface.
4.  **Storage:** **SQLite** embedded in the Core for task persistence.
5.  **Platform Integration:**
    *   **Android:** Foreground Service for reliable background downloads (`android/`).
    *   **Desktop:** Native messaging host for browser communication (`extensions/native-host/`).

## Tech Stack

*   **Core:** Rust (Cargo workspace).
*   **UI:** Flutter (Dart).
*   **Database:** SQLite.
*   **Interprocess Communication:** FFI (Flutter <-> Rust), Native Messaging (Browser <-> Core).

## Roadmap

### Phase 1: MVP Core (Current Focus)
*   [ ] UI: Home, Add Download Modal.
*   [ ] Engine: Segmented downloading, Resume support, SQLite DB integration.
*   [ ] Basic Management: Pause/Resume, Queue, Global Speed Limit.
*   [ ] Android: Foreground Service implementation.

### Phase 2: Quality & Stability
*   [ ] Advanced Scheduler.
*   [ ] Better Error Handling (human-readable codes) & Logging.
*   [ ] Desktop Tray integration.
*   [ ] Import/Export Tasks.

### Phase 3: Browser Integration
*   [ ] Browser Extensions (Chrome/Firefox).
*   [ ] Native Messaging Host integration.
*   [ ] Context menu "Download with SDM".

### Phase 4: Power Features
*   [ ] Media Grabber (m3u8/dash).
*   [ ] Checksum verification.
*   [ ] Mirror URL support.
*   [ ] Remote Control.

## Directory Structure

*   `core/`: Rust library containing the download engine.
*   `core-ffi/`: Rust crate exposing functionality to Dart.
*   `ui/`: Flutter application.
*   `android/`: Android-specific wrapper and service logic.
*   `extensions/`: Browser extension source code and native hosts.
*   `cli/`: Rust CLI for testing the engine without UI.
*   `daemon/`: Background process runner (mostly for desktop/testing).
*   `docs/`: Architecture and design documentation (See `specification_sdm.md`).

## Build & Run Instructions

### Rust Components
Run from project root:
```bash
# Build Core
cargo build -p idm-core

# Run CLI (Test)
IDM_DB=./idm.db cargo run -p idm-cli -- add <url>
IDM_DB=./idm.db cargo run -p idm-cli -- run
```

### Flutter UI
```bash
cd ui
flutter run
```

### Android
Build via Gradle from `android/` or run via Flutter (which wraps the Android project).

## Development Conventions

*   **Workspace:** Rust workspace. Use `-p <package_name>` to target crates.
*   **Database:** `IDM_DB` env var specifies SQLite DB path for CLI/Daemon.
*   **FFI:** Changes to `core` logic must be exposed via `core-ffi` and generated for Flutter.
*   **Reference:** See `docs/specification_sdm.md` for the detailed product spec.
