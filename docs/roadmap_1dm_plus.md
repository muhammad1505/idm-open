# IDM-Open Roadmap: 1DM+ Features Integration

This document outlines the roadmap to reach feature parity with 1DM+ (formerly IDM+), based on the request to "Complete Features".

## implemented Features (Phase 1)
- [x] **Cyberpunk UI**: Dark theme by default, matching the "Advanced" aesthetic.
- [x] **Basic Downloader**: Multi-part downloading (segmentation) via Rust Core.
- [x] **Built-in Browser**: Added `webview_flutter` based browser.
- [x] **Video Sniffer (Basic)**: Detects `.mp4`, `.mkv`, etc. in the browser and offers download.
- [x] **Smart Download (Clipboard)**: Auto-detects URLs from clipboard when adding a task.

## Remaining Features (Phase 2 & 3)

### 1. Torrent Support (High Priority)
*   **Goal**: Download files using `.torrent` files or Magnet links.
*   **Strategy**:
    *   Integrate a Rust BitTorrent library into `core`.
    *   Recommended Crate: `librustorrent` or `rqbit`.
    *   **Architecture**: Create a `TorrentEngine` alongside the HTTP `DownloadEngine`.
    *   **UI**: Add a specific tab or filter for Torrents.

### 2. HLS / m3u8 Video Support
*   **Goal**: Download streaming videos (HLS) and merge TS segments.
*   **Strategy**:
    *   **Core**: Add `m3u8-rs` to parse playlists.
    *   **Logic**:
        1.  Detect `.m3u8` extension.
        2.  Download Master Playlist -> Select highest quality.
        3.  Download Media Playlist.
        4.  Download all TS segments.
        5.  Merge segments using `ffmpeg` (via CLI or library) or simple binary concatenation (if possible).
    *   **Sniffer**: Update Browser Sniffer to detect `application/vnd.apple.mpegurl`.

### 3. Advanced Browser Features
*   **AdBlock**: Inject JavaScript to block common ad domains.
*   **Multi-Tab**: Implement a Tab Manager in Flutter.
*   **Incognito Mode**: Use `WebViewController` with an ephemeral profile.

### 4. Background Service
*   **Goal**: Keep downloading when app is closed.
*   **Current State**: `daemon` crate exists.
*   **Next Step**: Integrate `WorkManager` (Android) or `Foreground Service` (already partially in `android/`) to keep the Rust Core alive.

## How to Continue
1.  **Run dependencies**: `cd ui && flutter pub get`
2.  **Build Core**: `cargo build -p idm-core`
3.  **Run App**: `cd ui && flutter run`
