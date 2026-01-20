# IDM-Open

Open-source, cross-platform download manager targeting Android, Windows, and Linux.

This repo contains a Rust core engine and a Flutter UI. The core is designed to deliver IDM-class features (multi-part download, resume, scheduler, throttling, proxy, mirror fallback, checksum verification), while the UI and platform integrations are layered on top.

## Scope
- Target OS: Android, Windows, Linux
- Excluded: iOS, macOS (by request)
- License: MIT

## Structure
- core/     Rust core engine (library)
- core-ffi/ C ABI layer for Flutter and native hosts
- cli/      CLI wrapper for testing and automation
- daemon/   Background runner for queued tasks
- ui/       Flutter UI
- extensions/  Desktop browser extension + native messaging host notes
- android/  Android integration notes
- scripts/  Packaging helpers
- docs/     Architecture, schema, and roadmap

## Status
Core engine is functional with segmented downloads, resume via SQLite, throttling, retries, proxy/auth, mirror fallback, checksum verification, page-to-direct resolution (Pixeldrain, Google Drive, Mediafire + generic HTML), and auto filename from headers/URL. UI and platform integrations are the next major focus.

Note: Mega.nz links require Mega SDK integration (not implemented yet).

## Build (core)
```
cd /data/data/com.termux/files/home/idm-open
cargo build -p idm-core
```

## Build (CLI)
```
cargo build -p idm-cli
```

## Build (Daemon)
```
cargo build -p idm-daemon
```

## Run (CLI)
```
IDM_DB=/data/data/com.termux/files/home/idm-open/idm.db cargo run -p idm-cli -- add <url> [dest]
IDM_DB=/data/data/com.termux/files/home/idm-open/idm.db cargo run -p idm-cli -- run
```

If `dest` is omitted, the filename is taken from headers/URL and the download dir defaults to `/storage/emulated/0/Download` on Android (after `termux-setup-storage`).

## Run (Daemon)
```
IDM_DB=/data/data/com.termux/files/home/idm-open/idm.db cargo run -p idm-daemon -- --interval 2
```

## Services
See `services/README.md` for systemd user service and Termux scripts.

## UI
See `ui/README.md` for Flutter setup and FFI notes.

## Next steps
- Hook Android wrapper to core-ffi (JNI/FFI)
- Package installers for Windows/Linux and Android APK

See docs/architecture.md and docs/roadmap.md for details.
