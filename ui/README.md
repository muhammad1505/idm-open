# Flutter UI

This folder contains a minimal Flutter UI wired to `core-ffi` using Dart FFI.

## Setup
```
cd ui
flutter pub get
```

## Build (Android)
```
cd ui
flutter create --platforms android --project-name idm_open --org com.idmopen --overwrite .
flutter pub get
flutter build apk --debug
```

## CI build
GitHub Actions workflow `Build Android APK` builds a debug APK and uploads it as
the `idm-open-debug-apk` artifact.

## FFI notes
- Android/Linux uses `libidm_core_ffi.so`
- Windows uses `idm_core_ffi.dll`
- DB path is created under app documents: `idm_open/idm.db`

## Usage
- Add a URL (dest optional)
- Queue is stored in SQLite and can be consumed by the daemon
