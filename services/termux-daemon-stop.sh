#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PID_FILE="$HOME/.cache/idm-open/daemon.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "daemon not running"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "daemon stopped"
else
  echo "daemon not running"
fi

rm -f "$PID_FILE"

if command -v termux-wake-unlock >/dev/null 2>&1; then
  termux-wake-unlock || true
fi
