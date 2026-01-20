# Desktop browser integration

## Flow
1) Extension listens to context menu or auto-capture downloads (optional)
2) Extension sends JSON payload to native messaging host
3) Native host enqueues task into SQLite (IDM_DB)

## Payload example
```
{
  "url": "https://example.com/file.zip",
  "dest_path": "/home/user/Downloads/file.zip"
}
```

## Chrome/Edge (MV3)
- Load unpacked extension from `extensions/chrome`
- Native host manifest template: `extensions/native-host/com.idmopen.native.json`
- Configure auto-capture in extension options

## Firefox (MV2)
- Load temporary add-on from `extensions/firefox`
- Native host manifest template: `extensions/native-host/com.idmopen.native.firefox.json`
- Configure auto-capture in extension options

## Build native host
```
cargo build -p idm-native-host
```

## Install native host
```
extensions/install_native_host.sh --host /abs/path/to/idm-native-host --chrome-id <EXT_ID>
extensions/install_native_host.sh --host /abs/path/to/idm-native-host --firefox-id <EXT_ID>
```

## Environment
- `IDM_DB` sets the SQLite path for queuing downloads
- `IDM_DOWNLOAD_DIR` sets default download folder (when dest_path missing)

## Daemon
Run `idm-daemon` in the background to consume queued tasks.
