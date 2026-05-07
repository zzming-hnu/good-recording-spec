#!/usr/bin/env bash
# Build a Universal Binary (arm64 + x86_64) macOS .app bundle.
#
# Source of truth for the build pipeline:
#   home-spec/specs/001-good-recording/quickstart.md §3
#
# Prerequisites:
#   - Full Xcode (not just Command Line Tools)
#   - XcodeGen (`brew install xcodegen`)

set -euo pipefail

cd "$(dirname "$0")/.."

# Regenerate Xcode project from project.yml if XcodeGen is available
# (project.yml is the source of truth; .xcodeproj is gitignored).
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
elif [[ ! -d GoodRecording.xcodeproj ]]; then
    echo "❌ XcodeGen not found and GoodRecording.xcodeproj missing." >&2
    echo "   Install XcodeGen: brew install xcodegen" >&2
    exit 1
fi

mkdir -p build

xcodebuild archive \
    -scheme GoodRecording \
    -configuration Release \
    -archivePath build/GoodRecording.xcarchive \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO

xcodebuild -exportArchive \
    -archivePath build/GoodRecording.xcarchive \
    -exportPath build/Release \
    -exportOptionsPlist scripts/ExportOptions.plist

echo "✅ Universal Binary built at build/Release/GoodRecording.app"

# Verify both architectures present (Constitution IV requirement).
BIN="build/Release/GoodRecording.app/Contents/MacOS/GoodRecording"
if [[ -f "$BIN" ]]; then
    lipo -info "$BIN"
fi
