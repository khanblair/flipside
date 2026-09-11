#!/bin/bash
# Signs (Developer ID Application), notarizes, and staples Flipside.app.
#
# Requires, on this machine, before running:
#   - A "Developer ID Application" certificate in the login keychain.
#   - A notarytool keychain profile created once via:
#       xcrun notarytool store-credentials "flipside-notary" \
#         --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>
#
# Not executed as part of this build — requires the user's own Apple
# Developer ID credentials, which are not available in this environment.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/Flipside.app"
ZIP_PATH="$ROOT_DIR/build/Flipside.zip"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your \"Developer ID Application: Name (TEAMID)\" identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-flipside-notary}"

if [ ! -d "$APP_PATH" ]; then
  echo "error: $APP_PATH not found — run scripts/make_app_bundle.sh first" >&2
  exit 1
fi

echo "Signing $APP_PATH ..."
codesign --force --deep --options runtime \
  --entitlements "$ROOT_DIR/Packaging/Flipside.entitlements" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_PATH"

echo "Verifying signature has no sandbox entitlement ..."
if codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
  echo "error: sandbox entitlement present — this must not be set (spec §11)" >&2
  exit 1
fi

echo "Zipping for notarization ..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Submitting to notarytool (profile: $NOTARY_PROFILE) ..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling ticket ..."
xcrun stapler staple "$APP_PATH"

echo "Verifying Gatekeeper acceptance ..."
spctl -a -vv "$APP_PATH"

echo "Done: $APP_PATH is signed, notarized, and stapled."
