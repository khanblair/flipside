#!/bin/bash
# Assembles the SPM-built Flipside executable into a proper .app bundle.
# Usage: scripts/make_app_bundle.sh [Debug|Release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Flipside.app"
export PKG_CONFIG_PATH="$(brew --prefix sqlcipher)/lib/pkgconfig"

# Only the minimal cleanup a rebuild actually needs: stop whatever's running
# so it isn't holding the old binary open. This does NOT reset Accessibility
# permission or remove the bundle -- that's scripts/uninstall.sh, a separate,
# explicit action, since resetting permission on every single rebuild forces
# a re-grant after every build and makes iterating unusable.
killall Flipside 2>/dev/null || true
sleep 1

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

# install_name_tool invalidates whatever ad-hoc signature the linker applied
# (macOS refuses to launch a binary whose signature no longer matches its
# content — SIGKILL "Code Signature Invalid"). Re-sign ad-hoc so the bundle
# is launchable for local testing. scripts/notarize.sh replaces this with a
# real Developer ID signature for distribution.
codesign --force --deep --sign - "$APP_DIR"

echo "Assembled $APP_DIR"
