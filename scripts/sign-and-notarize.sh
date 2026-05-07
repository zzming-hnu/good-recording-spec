#!/usr/bin/env bash
# Codesign with Developer ID + notarize via notarytool + staple.
#
# Source of truth for this pipeline:
#   home-spec/specs/001-good-recording/quickstart.md §3
#   home-spec/specs/001-good-recording/research.md R7
#
# Setup (one time):
#   xcrun notarytool store-credentials good-recording-notary \
#       --apple-id "you@example.com" \
#       --team-id "YOUR_TEAM_ID" \
#       --password "<app-specific-password>"
#
# Usage:
#   ./scripts/sign-and-notarize.sh [path/to/GoodRecording.app]

set -euo pipefail

APP_PATH="${1:-build/Release/GoodRecording.app}"
PROFILE="${NOTARYTOOL_PROFILE:-good-recording-notary}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App bundle not found at $APP_PATH" >&2
    echo "   Run scripts/build-universal.sh first." >&2
    exit 1
fi

ZIP_PATH="$(dirname "$APP_PATH")/$(basename "$APP_PATH" .app).zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "→ Submitting to Apple notarization service (this may take a few minutes)…"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$PROFILE" \
    --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# Final Gatekeeper check (Constitution IV —分发包首次启动 MUST 不出现警告).
spctl --assess --verbose=4 --type execute "$APP_PATH"

echo "✅ App signed, notarized, and stapled at $APP_PATH"
