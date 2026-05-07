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

# Pre-flight: full Xcode required (Command Line Tools alone is NOT enough).
# Reports the issue with the spec's 三要素 (what / why / next step) format
# instead of letting xcodebuild's obscure error reach the user.
DEV_DIR="$(xcode-select -p 2>/dev/null || echo '<not set>')"
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    echo "" >&2
    echo "❌ 没有检测到完整的 Xcode (当前 xcode-select 指向: $DEV_DIR)" >&2
    echo "" >&2
    echo "   原因: 本脚本走 \`xcodebuild archive\` 构建 macOS .app，必须使用" >&2
    echo "         完整的 Xcode.app；只有 Command Line Tools (CLT) 是不够的。" >&2
    echo "" >&2
    echo "   下一步:" >&2
    echo "     1. 安装完整 Xcode:" >&2
    echo "          - App Store 搜索 'Xcode' 安装 (推荐, 自动签名链)" >&2
    echo "          - 或 https://developer.apple.com/download/all/ 下载 .xip" >&2
    echo "     2. 切换 xcode-select 指向新装的 Xcode:" >&2
    echo "          sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    echo "     3. 同意许可:  sudo xcodebuild -license accept" >&2
    echo "     4. 重新运行:  ./scripts/build-universal.sh" >&2
    echo "" >&2
    exit 1
fi

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
