# Services

## Linux (systemd user)
- Copy `services/idm-open.service` to `~/.config/systemd/user/`
- Enable and start:
```
systemctl --user enable --now idm-open.service
```

## Termux/Android
- First time:
```
termux-setup-storage
```
- Optional: auto-set download dir for new shells
```
cat services/termux-profile.sh >> ~/.profile
```
- Build daemon:
```
cargo build -p idm-daemon
```
- Start:
```
services/termux-daemon.sh
```
- Stop:
```
services/termux-daemon-stop.sh
```

Environment:
- `IDM_DB` path for SQLite queue
- `IDM_DOWNLOAD_DIR` default download directory (defaults to `/storage/emulated/0/Download` if available)
- `IDM_DAEMON_BIN` optional custom path to idm-daemon
