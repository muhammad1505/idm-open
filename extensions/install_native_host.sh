#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install_native_host.sh --host /path/to/idm-native-host [--chrome-id ID] [--firefox-id ID] [--chromium]

Options:
  --host         Path to idm-native-host binary
  --chrome-id    Chrome/Edge extension ID (required for Chrome)
  --firefox-id   Firefox extension ID (from manifest "applications.gecko.id")
  --chromium     Install to Chromium path instead of Google Chrome
USAGE
}

HOST=""
CHROME_ID=""
FIREFOX_ID=""
USE_CHROMIUM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --chrome-id)
      CHROME_ID="$2"
      shift 2
      ;;
    --firefox-id)
      FIREFOX_ID="$2"
      shift 2
      ;;
    --chromium)
      USE_CHROMIUM=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "--host is required"
  usage
  exit 1
fi

if [[ ! -x "$HOST" ]]; then
  echo "Host binary not executable: $HOST"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "$CHROME_ID" ]]; then
  if [[ $USE_CHROMIUM -eq 1 ]]; then
    CHROME_DIR="$HOME/.config/chromium/NativeMessagingHosts"
  else
    CHROME_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
  fi
  mkdir -p "$CHROME_DIR"
  TEMPLATE="$ROOT_DIR/native-host/com.idmopen.native.json"
  TARGET="$CHROME_DIR/com.idmopen.native.json"
  sed \
    -e "s|/path/to/idm-native-host|$HOST|" \
    -e "s|chrome-extension://YOUR_EXTENSION_ID/|chrome-extension://$CHROME_ID/|" \
    "$TEMPLATE" > "$TARGET"
  echo "Installed Chrome manifest to $TARGET"
fi

if [[ -n "$FIREFOX_ID" ]]; then
  FIREFOX_DIR="$HOME/.mozilla/native-messaging-hosts"
  mkdir -p "$FIREFOX_DIR"
  TEMPLATE="$ROOT_DIR/native-host/com.idmopen.native.firefox.json"
  TARGET="$FIREFOX_DIR/com.idmopen.native.json"
  sed \
    -e "s|/path/to/idm-native-host|$HOST|" \
    -e "s|idm-open@example.com|$FIREFOX_ID|" \
    "$TEMPLATE" > "$TARGET"
  echo "Installed Firefox manifest to $TARGET"
fi

if [[ -z "$CHROME_ID" && -z "$FIREFOX_ID" ]]; then
  echo "Nothing to install: provide --chrome-id and/or --firefox-id"
  exit 1
fi
