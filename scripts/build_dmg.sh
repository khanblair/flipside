#!/bin/bash
# Packages the signed/notarized Flipside.app into a distributable DMG.
# Run scripts/make_app_bundle.sh and scripts/notarize.sh first.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/Flipside.app"
DMG_PATH="$ROOT_DIR/build/Flipside.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found — run scripts/make_app_bundle.sh first" >&2
  exit 1
fi

rm -f "$DMG_PATH"
hdiutil create -volname "Flipside" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "Verifying DMG ..."
hdiutil verify "$DMG_PATH"

echo "Done: $DMG_PATH"
