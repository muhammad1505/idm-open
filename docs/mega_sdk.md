# Mega SDK integration (planned)

Mega links require the official Mega SDK (C/C++) for authenticated access and file downloads.

## Planned steps
1) Add Mega SDK as a submodule or vendor binary per OS.
2) Create a Rust FFI layer (bindgen or hand-written) for minimal APIs:
   - login/anonym
   - get node by URL
   - start download
3) Expose a `mega` feature flag in `idm-core`.
4) Implement `net` provider for Mega that streams data into segments.

## Constraints
- Mega requires OAuth/token handling and node resolution.
- On Android, needs JNI + bundled .so from Mega SDK.
- On Windows/Linux, needs build scripts to fetch or compile Mega SDK.

## Current status
- Resolver detects Mega and returns an "unsupported" error.
