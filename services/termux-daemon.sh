#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DEFAULT="$ROOT_DIR/target/debug/idm-daemon"
BIN_PATH="${IDM_DAEMON_BIN:-$BIN_DEFAULT}"

TERMUX_HOME="/data/data/com.termux/files/home"
HOME_DIR="$HOME"
if [[ -d "$TERMUX_HOME" ]]; then
  HOME_DIR="$TERMUX_HOME"
fi

PID_DIR="$HOME_DIR/.cache/idm-open"
PID_FILE="$PID_DIR/daemon.pid"
LOG_FILE="$PID_DIR/daemon.log"

mkdir -p "$PID_DIR"

if [[ -f "$PID_FILE" ]]; then
  if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "daemon already running (pid $(cat "$PID_FILE"))"
    exit 0
  else
    rm -f "$PID_FILE"
  fi
fi

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
fi

if [[ ! -x "$BIN_PATH" ]]; then
  echo "daemon binary not found: $BIN_PATH"
  echo "build with: cargo build -p idm-daemon"
  exit 1
fi

export IDM_DB="${IDM_DB:-$HOME_DIR/.idm-open/idm.db}"

if [[ -z "${IDM_DOWNLOAD_DIR:-}" ]]; then
  if [[ -d "/storage/emulated/0/Download" ]]; then
    export IDM_DOWNLOAD_DIR="/storage/emulated/0/Download"
  elif [[ -d "/sdcard/Download" ]]; then
    export IDM_DOWNLOAD_DIR="/sdcard/Download"
  else
    export IDM_DOWNLOAD_DIR="$HOME_DIR/downloads"
  fi
fi

mkdir -p "$(dirname "$IDM_DB")"

nohup "$BIN_PATH" --interval 2 >> "$LOG_FILE" 2>&1 &
PID=$!

echo $PID > "$PID_FILE"

sleep 0.5
if kill -0 "$PID" 2>/dev/null; then
  echo "daemon started (pid $PID)"
else
  echo "daemon failed to start; see $LOG_FILE"
  rm -f "$PID_FILE"
  exit 1
fi
