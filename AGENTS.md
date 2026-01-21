# Repository Guidelines

## Project Structure & Module Organization
- `core/`: Rust download engine (library) and core logic.
- `core-ffi/`: C ABI surface used by Flutter and native hosts.
- `cli/`: Rust CLI for local testing and automation.
- `daemon/`: Background runner for queued tasks.
- `ui/`: Flutter UI wired to `core-ffi`.
- `android/`: Android wrapper and intent handling notes.
- `extensions/`: Browser extension sources and native messaging host.
- `services/`: systemd user unit and Termux helper scripts.
- `scripts/`: Packaging helpers for Linux/Windows.
- `docs/`: Architecture, schema, and roadmap documentation.

## Build, Test, and Development Commands
```bash
# Build Rust components
cargo build -p idm-core
cargo build -p idm-cli
cargo build -p idm-daemon

# Run CLI (set DB location)
IDM_DB=./idm.db cargo run -p idm-cli -- add <url> [dest]
IDM_DB=./idm.db cargo run -p idm-cli -- run

# Run daemon
IDM_DB=./idm.db cargo run -p idm-daemon -- --interval 2

# Core tests
cargo test -p idm-core

# Flutter UI
cd ui && flutter run
```
Packaging: `./scripts/package-linux.sh` (Linux) or `./scripts/package-windows.ps1` (Windows host).

## Coding Style & Naming Conventions
- Rust is edition 2021; keep crate names `idm-core`, `idm-cli`, `idm-daemon`.
- Prefer standard formatters: `cargo fmt` for Rust and `dart format`/`flutter format` for UI code.
- Keep FFI changes in sync: if core APIs change, update `core-ffi/` and any Dart bindings.

## Testing Guidelines
- Rust tests live in `core/src/tests.rs` using `#[test]` and `test_*` function names.
- Add unit tests for new engine behavior; run `cargo test -p idm-core` before PRs.
- No explicit coverage target is defined; focus on critical download paths.

## Commit & Pull Request Guidelines
- Follow the existing Conventional Commit style when possible: `feat(ui): ...`, `fix(ci): ...`.
- PRs should include a brief summary, testing evidence (commands run), and linked issues.
- For UI changes, include screenshots or a short screen recording.

## Configuration & Environment
- `IDM_DB`: SQLite path for queue/state (e.g., `./idm.db`).
- `IDM_DOWNLOAD_DIR`: default download directory for new tasks.
- `IDM_DAEMON_BIN`: override daemon binary path for scripts.
- On Termux, run `termux-setup-storage` before downloads.
