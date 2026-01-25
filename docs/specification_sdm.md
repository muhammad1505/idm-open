# Spesifikasi Smart Download Manager (SDM)

## 1. Visi Produk
**Tujuan Utama:** Download cepat, stabil, bisa resume, multi-connection, antrian/scheduler, dan mudah digunakan lintas platform (Android, Windows, Linux).

**Nilai Jual:**
*   **Download Engine Kuat:** Segment/multipart, retry, resume, checksum.
*   **Cross-platform UI:** Konsisten di semua OS.
*   **Browser Integration:** 1-klik "Download with SDM".
*   **Manajemen:** Queue + Scheduler ala IDM.
*   **Fitur Tambahan:** Media grabber, Remote control (opsional).

## 2. Target Platform & Batasan
*   **Android:** App + Foreground Service (mengatasi batasan background process). Menggunakan Storage Access Framework (SAF).
*   **Windows:** Desktop App + Background Service (opsional). Native messaging host untuk browser.
*   **Linux:** Desktop App (AppImage/DEB/RPM).
*   **Browser Extensions:** Chrome, Edge, Firefox.

## 3. Pilihan Teknologi (Opsi A - Terpilih)
*   **UI:** Flutter (Stabil untuk Android/Windows/Linux).
*   **Core Engine:** Rust (Performa tinggi, memory safety, concurrency).
*   **Komunikasi:** FFI (Foreign Function Interface) via `flutter_rust_bridge`.
*   **Database:** SQLite.

## 4. Arsitektur
### Komponen Utama
1.  **SDM UI App (Flutter):** Antarmuka pengguna.
2.  **SDM Core Engine (Rust):** Logika download, networking, file I/O.
3.  **Storage Layer (SQLite):** Persistensi task dan setting.
4.  **Browser Integration:** Extension (JS) + Native Messaging Host (Rust).
5.  **Platform Services:** Android Foreground Service, Desktop Tray/Service.

### Alur Data
`User input URL` -> `UI kirim "CreateTask"` -> `Engine cek metadata & buat segments` -> `Download jalan` -> `Update DB` -> `UI render progress realtime`.

## 5. Fitur Utama

### MVP (Fase 1)
*   [ ] Add URL (http/https)
*   [ ] Pause/Resume
*   [ ] Multi-connection (Segmented Download)
*   [ ] Auto resume after restart
*   [ ] Queue & Speed Limit
*   [ ] Basic Scheduler
*   [ ] File rename + Folder selection
*   [ ] Error handling + Retry + Backoff
*   [ ] Import/Export Task (JSON)

### Pro (Fase Lanjutan)
*   [ ] Browser Extension
*   [ ] Video/Audio Grabber
*   [ ] Mirror URL
*   [ ] Checksum Verify
*   [ ] Captcha/Cookie Import
*   [ ] Remote Control
*   [ ] Cloud Sync

## 6. Detail Download Engine (Rust)
### Strategi Network
*   HTTP(S) dengan Range Header.
*   Validasi resume via `ETag` dan `Last-Modified`.
*   Redirect handling & Proxy support.

### Segmentasi (Rekomendasi)
*   < 20MB: 1 koneksi
*   20–200MB: 4 koneksi
*   200MB–2GB: 8 koneksi
*   > 2GB: 8–16 koneksi

### Scheduler & Queue
*   **Global Limit:** Max running tasks (misal 3).
*   **Task Limit:** Max connections per task (misal 8).
*   **Status:** Queued, Running, Paused, Completed, Failed.

### Stabilitas
*   Exponential Backoff (1s -> ... -> 60s).
*   Handling 403/401 (prompt update cookie).
*   File Writing: `.sdm.part` dengan random access write. Rename saat final.

### Event System
Broadcast: `TaskCreated`, `MetadataFetched`, `Progress`, `SegmentProgress`, `TaskCompleted`, `TaskFailed`.

## 7. Database (SQLite)
### Tabel `tasks`
*   `id`, `url`, `final_file_name`, `save_dir`, `status`
*   `total_bytes`, `downloaded_bytes`, `supports_range`, `etag`
*   `max_connections`, `priority`, `speed_limit`, `headers_json`

### Tabel `segments`
*   `id`, `task_id`, `start_byte`, `end_byte`, `downloaded_bytes`
*   `status`, `retry_count`

### Tabel `settings`
*   Konfigurasi global (folder default, tema, limit).

## 8. UI/UX (Flutter)
*   **Layar:** Home (Tabs: All/Downloading/...), Add Download Modal, Task Detail, Settings.
*   **Komponen:** Download Card (Progress, Speed, ETA), Tray Icon, Notification.
*   **Interaksi:** Drag & drop URL, Auto-detect clipboard.

## 9. Integrasi Browser
*   **Extension:** Intercept link / Context menu.
*   **Native Host:** Menerima pesan dari extension, memanggil Core/UI.

## 10. Roadmap Pengembangan
1.  **Fase 1 (MVP Core):** UI Home, Engine Segmented+Resume, DB, Android Service.
2.  **Fase 2 (Quality):** Scheduler, Error logs, Tray, Import/Export.
3.  **Fase 3 (Browser):** Extension + Native Host.
4.  **Fase 4 (Power):** Grabber, Checksum, Remote.
