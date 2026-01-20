# Gemini Project Context: IDM-Open

This document provides context for the `idm-open` project, an open-source, cross-platform download manager designed for Android, Windows, and Linux.

## Project Overview

**Goal:** Create a feature-rich download manager with IDM-class capabilities (segmentation, resume, scheduling, throttling) using a performant Rust core and a cross-platform Flutter UI.

**Key Features:**
*   Multi-part downloading.
*   Resume capability via SQLite persistence.
*   Scheduling and Throttling.
*   Proxy/Auth support.
*   Mirror fallback.
*   Checksum verification.
*   Page-to-direct link resolution (Pixeldrain, Google Drive, Mediafire).

## Architecture

The project follows a layered architecture:

1.  **Core (`core/`):** The heavy lifter written in Rust. Handles networking, file I/O, database interactions (SQLite), and download logic.
2.  **FFI Layer (`core-ffi/`):** Exposes the core functionality via a C ABI, allowing interaction with Flutter and native system hosts.
3.  **Interfaces:**
    *   **CLI (`cli/`):** A Rust-based command-line interface for testing and automation.
    *   **Daemon (`daemon/`):** A background service for running queued tasks.
    *   **UI (`ui/`):** A Flutter application providing the user interface.
    *   **Android Wrapper (`android/`):** Native Android code to wrap the core/UI and handle system intents.
    *   **Extensions (`extensions/`):** Browser extensions (Chrome/Firefox) and a native messaging host.

## Tech Stack

*   **Core:** Rust (Cargo workspace).
*   **UI:** Flutter (Dart).
*   **Android:** Kotlin/Java (Gradle).
*   **Database:** SQLite (embedded in Core).
*   **Interprocess Communication:** FFI (Foreign Function Interface), Native Messaging.

## Directory Structure

*   `core/`: Rust library containing the download engine.
*   `core-ffi/`: C-compatible interface for the core.
*   `cli/`: CLI tool to control the engine.
*   `daemon/`: Background process runner.
*   `ui/`: Flutter mobile/desktop application.
*   `android/`: Android-specific wrapper project.
*   `extensions/`: Browser extension source code and native hosts.
*   `docs/`: Architecture and design documentation.
*   `services/`: Systemd services and Termux helper scripts.

## Build & Run Instructions

### Rust Components (Core, CLI, Daemon)

Run from the project root (`/data/data/com.termux/files/home/idm-open`):

**Build Core:**
```bash
cargo build -p idm-core
```

**Build & Run CLI:**
```bash
# Add a download
IDM_DB=./idm.db cargo run -p idm-cli -- add <url>

# Run the engine (start downloading)
IDM_DB=./idm.db cargo run -p idm-cli -- run
```

**Build & Run Daemon:**
```bash
IDM_DB=./idm.db cargo run -p idm-daemon -- --interval 2
```

### Flutter UI

Navigate to the `ui` directory:
```bash
cd ui
flutter run
```

### Android APK

Build via Gradle from the `android` directory (requires Android SDK setup):
```bash
cd android
./gradlew assembleDebug
```

## Development Conventions

*   **Workspace:** This is a Rust workspace. Use `-p <package_name>` to target specific crates (e.g., `idm-core`, `idm-cli`).
*   **Database:** The core relies on an SQLite database. The `IDM_DB` environment variable specifies its location.
*   **FFI:** Changes to `core` logic that need to be exposed to the UI must be reflected in `core-ffi`.
*   **Platform Targets:** Primary testing occurs on Android (via Termux) and Linux.

## Current State

*   **Core:** Functional (segments, resume, throttling, checksums implemented).
*   **Mega.nz:** Pending SDK integration.
*   **UI:** In development (Flutter).
*   **Android:** Wrapper integration pending.
