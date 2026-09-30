#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="$ROOT_DIR/.build/apple/Products/Release/WarawaraPet"
APP_DIR="$ROOT_DIR/dist/WarawaraPet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [ ! -f "$BIN_PATH" ]; then
    echo "error: release binary not found at $BIN_PATH" >&2
    echo "run: swift build -c release" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/WarawaraPet"
chmod +x "$MACOS_DIR/WarawaraPet"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

rm -f "$ROOT_DIR/dist/WarawaraPet.zip"
ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/WarawaraPet.zip"

echo "packaged: $ROOT_DIR/dist/WarawaraPet.zip"
