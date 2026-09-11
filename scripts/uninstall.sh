#!/bin/bash
# Stops Flipside if running, removes the locally-built .app, and clears the
# stale Accessibility permission grant tied to the old build's signature
# (every rebuild re-signs ad-hoc, which macOS treats as a different app for
# permission purposes -- this is what causes multiple confusing "Flipside"
# entries in System Settings > Privacy & Security > Accessibility).
#
# Does NOT touch the user's notes: ~/Library/Application Support/Flipside
# (the encrypted database) and the Keychain item holding its key are user
# data, not build artifacts, and survive a reinstall like any normal app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Flipside.app"

echo "Stopping Flipside if running..."
killall Flipside 2>/dev/null || true
sleep 1

if [ -d "$APP_DIR" ]; then
  echo "Removing $APP_DIR ..."
  rm -rf "$APP_DIR"
fi

echo "Clearing Accessibility permission grant for com.flipside.app..."
if tccutil reset Accessibility com.flipside.app 2>/dev/null; then
  echo "  cleared -- you'll be prompted again on next launch"
else
  echo "  skipped (tccutil unavailable or nothing to reset) -- remove stale entries manually via System Settings > Privacy & Security > Accessibility if needed"
fi

echo "Uninstall complete."
