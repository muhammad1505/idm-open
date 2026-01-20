# Android integration

## Share/intent flow
- Register intent for ACTION_SEND and ACTION_VIEW (http/https)
- Parse URL from shared text or intent data
- Open app and enqueue task via core-ffi

## Wrapper skeleton
A minimal Kotlin wrapper exists at `android/wrapper/` with:
- `MainActivity` that forwards shared URLs to a foreground service
- `DownloadForegroundService` stub to enqueue downloads (TODO: JNI/FFI bridge)

## Notes
- Auto-capture from all browsers is not possible without user action
- Use foreground service for long downloads
- Request runtime permissions for storage access
