#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/linux"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/extensions" "$DIST_DIR/services"

cd "$ROOT_DIR"

cargo build --release -p idm-cli -p idm-daemon -p idm-native-host

cp -f target/release/idm-cli "$DIST_DIR/bin/"
cp -f target/release/idm-daemon "$DIST_DIR/bin/"
cp -f target/release/idm-native-host "$DIST_DIR/bin/"

cp -r extensions/chrome "$DIST_DIR/extensions/"
cp -r extensions/firefox "$DIST_DIR/extensions/"
cp -r extensions/native-host "$DIST_DIR/extensions/"
cp extensions/install_native_host.sh "$DIST_DIR/extensions/"

cp services/idm-open.service "$DIST_DIR/services/"
cp services/README.md "$DIST_DIR/services/"

cp README.md "$DIST_DIR/"

TAR_NAME="$ROOT_DIR/dist/idm-open-linux.tar.gz"
rm -f "$TAR_NAME"

tar -czf "$TAR_NAME" -C "$ROOT_DIR/dist" linux

echo "Created $TAR_NAME"
