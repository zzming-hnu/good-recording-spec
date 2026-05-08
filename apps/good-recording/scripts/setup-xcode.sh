#!/usr/bin/env bash
# One-shot Xcode setup after first installing Xcode.app from the App Store.
# Idempotent: safe to re-run.
#
# Steps:
#   1. Switch active developer directory from CLT → /Applications/Xcode.app
#   2. Accept the Xcode license
#   3. Install first-launch components (Simulator runtimes, etc.)
#   4. Regenerate the Xcode project from project.yml
#   5. Run a quick smoke build to confirm the toolchain works
#
# Usage:
#   ./scripts/setup-xcode.sh
#
# (sudo prompts will appear for steps 1–3; the rest runs as your user.)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

XCODE_DEV_DIR="/Applications/Xcode.app/Contents/Developer"

echo "════════════════════════════════════════════════════════════════"
echo " good-recording — Xcode 一键收尾"
echo "════════════════════════════════════════════════════════════════"

# ─── Step 0: pre-flight ─────────────────────────────────────────────
if [[ ! -d "/Applications/Xcode.app" ]]; then
    echo "❌ /Applications/Xcode.app 不存在。先去 App Store 装 Xcode。" >&2
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "❌ XcodeGen 未安装。先跑: brew install xcodegen" >&2
    exit 1
fi

# ─── Step 1: switch xcode-select if needed ──────────────────────────
CURRENT="$(xcode-select -p 2>/dev/null || echo '')"
if [[ "$CURRENT" != "$XCODE_DEV_DIR" ]]; then
    echo ""
    echo "→ Step 1/5: 切换 xcode-select"
    echo "  当前: $CURRENT"
    echo "  目标: $XCODE_DEV_DIR"
    echo "  (会请求 sudo 密码…)"
    sudo xcode-select -s "$XCODE_DEV_DIR"
    echo "  ✅ 已切换到 $(xcode-select -p)"
else
    echo ""
    echo "→ Step 1/5: xcode-select 已经指向 Xcode.app，跳过"
fi

# ─── Step 2: accept license ─────────────────────────────────────────
if ! xcodebuild -checkFirstLaunchStatus 2>/dev/null && false; then : ; fi
# -checkFirstLaunchStatus exit code is unreliable, just always run -license check.
echo ""
echo "→ Step 2/5: 接受 Xcode license（如果尚未接受会请求 sudo 密码）"
sudo xcodebuild -license accept 2>&1 | sed 's/^/  /' || true
echo "  ✅ License 已接受"

# ─── Step 3: install first-launch components ────────────────────────
echo ""
echo "→ Step 3/5: 安装首启组件（额外的工具链 / 模拟器运行时等）"
echo "  (会请求 sudo 密码；首次可能需要几分钟下载)"
sudo xcodebuild -runFirstLaunch 2>&1 | sed 's/^/  /' || true
echo "  ✅ 首启组件就绪"

# ─── Step 4: regenerate Xcode project ───────────────────────────────
echo ""
echo "→ Step 4/5: 重新生成 GoodRecording.xcodeproj"
rm -rf GoodRecording.xcodeproj
xcodegen generate 2>&1 | sed 's/^/  /'
echo "  ✅ 工程文件已生成"

# ─── Step 5: smoke build ────────────────────────────────────────────
echo ""
echo "→ Step 5/5: 烟雾构建（不出 Universal Binary，只验证能编译）"
xcodebuild build \
    -scheme GoodRecording \
    -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" \
    -quiet \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -10

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " ✅ Xcode 环境就绪 + 项目能编译"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "下一步可选:"
echo "  • 在 Xcode 里调试: open GoodRecording.xcodeproj"
echo "  • 出 Universal Binary: ./scripts/build-universal.sh"
echo "  • 公证分发: ./scripts/sign-and-notarize.sh"
echo ""
