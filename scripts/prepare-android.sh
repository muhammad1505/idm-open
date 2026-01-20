#!/usr/bin/env bash
set -euo pipefail

# This script builds the Rust core and copies it to the Android project's jniLibs folder.
# Run this before building the APK.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_APP_DIR="$ROOT_DIR/android/wrapper/app"
JNI_LIBS_DIR="$ANDROID_APP_DIR/src/main/jniLibs"

echo "Building Rust core (release)..."
cd "$ROOT_DIR"
cargo build --release -p idm-core-ffi

echo "Preparing jniLibs directory..."
mkdir -p "$JNI_LIBS_DIR/arm64-v8a"

SOURCE_LIB="$ROOT_DIR/target/release/libidm_core_ffi.so"
DEST_LIB="$JNI_LIBS_DIR/arm64-v8a/libidm_core_ffi.so"

if [ -f "$SOURCE_LIB" ]; then
    echo "Copying $SOURCE_LIB to $DEST_LIB"
    cp "$SOURCE_LIB" "$DEST_LIB"
    echo "Done. You can now build the APK."
else
    echo "Error: $SOURCE_LIB not found. Build failed?"
    exit 1
fi
