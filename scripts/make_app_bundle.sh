#!/bin/bash
# Assembles the SPM-built Flipside executable into a proper .app bundle.
# Usage: scripts/make_app_bundle.sh [Debug|Release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Flipside.app"
export PKG_CONFIG_PATH="$(brew --prefix sqlcipher)/lib/pkgconfig"

swift build -c "$CONFIG" --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT_DIR" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/Flipside"
if [ ! -f "$EXECUTABLE_PATH" ]; then
  echo "error: built executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/Flipside"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

# The executable links against Homebrew's libsqlcipher.dylib. For a
# self-contained, distributable .app (spec §11: direct distribution,
# no dependency on the end user having Homebrew), bundle that dylib and
# repoint the load command at it via @rpath.
SQLCIPHER_DYLIB="$(otool -L "$APP_DIR/Contents/MacOS/Flipside" | awk '/libsqlcipher/{print $1; exit}')"
if [ -n "$SQLCIPHER_DYLIB" ]; then
  cp -L "$SQLCIPHER_DYLIB" "$APP_DIR/Contents/Frameworks/libsqlcipher.dylib"
  install_name_tool -change "$SQLCIPHER_DYLIB" "@rpath/libsqlcipher.dylib" "$APP_DIR/Contents/MacOS/Flipside"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/Flipside" 2>/dev/null || true
else
  echo "warning: libsqlcipher.dylib dependency not found via otool -L; app may not be self-contained" >&2
fi

echo "Assembled $APP_DIR"
