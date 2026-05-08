#!/usr/bin/env bash
# good-recording — rebuild + reset TCC + reopen, in one shot.
#
# Why this exists: under self-signed dev certificates (the kind
# scripts/make-local-cert.sh creates), every rebuild changes the
# binary's cdhash, and macOS TCC doesn't carry the prior Screen
# Recording grant forward. This script bundles the recovery dance:
#
#   1. quit the running instance
#   2. clean DerivedData + xcodegen + xcodebuild
#   3. tccutil reset (so the next launch shows a fresh native dialog)
#   4. killall cfprefsd (so the next launch sees fresh UserDefaults)
#   5. open the new build
#
# After step 5 you click 开始录制 once → macOS shows the native dialog →
# allow → the System Settings panel opens → ensure GoodRecording is on
# → click "Quit & Reopen" → done.
#
# Idempotent: safe to re-run any time.
#
# Usage:
#   ./scripts/rebuild-and-reauth.sh            # full clean rebuild
#   ./scripts/rebuild-and-reauth.sh --fast     # skip DerivedData wipe
#                                              # (incremental rebuild)
#
# Source-of-truth doc: specs/001-good-recording/troubleshooting.md
# (in the home-spec sibling repo) — Issues 4, 5, 7, 8.

set -euo pipefail

# ─── Args ───────────────────────────────────────────────────────────
FAST=false
for arg in "$@"; do
    case "$arg" in
        --fast) FAST=true ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# \?//' | head -25
            exit 0
            ;;
        *)
            echo "Unknown arg: $arg" >&2
            exit 1
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUNDLE_ID="com.zzming.good-recording"
APP_NAME="GoodRecording"
DERIVED_GLOB="$HOME/Library/Developer/Xcode/DerivedData/${APP_NAME}-*"

echo "════════════════════════════════════════════════════════════════"
echo " good-recording — rebuild & reauth (fast=$FAST)"
echo "════════════════════════════════════════════════════════════════"

# ─── Step 1: Stop the running app (best effort) ────────────────────
echo ""
echo "→ Step 1/5: stopping any running instance"
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

if pgrep -x "$APP_NAME" >/dev/null; then
    # Some launchd-supervised debug instances can't be killed without rebooting.
    # That's OK — `open -n` below starts a fresh instance with a new PID and
    # the new cdhash. macOS handles two PIDs of the same bundle id by
    # auto-activating the newer one for foreground; the zombie is harmless
    # in the background. We keep going.
    echo "  ⚠️  Old instance is launchd-supervised and unkillable, ignoring."
    echo "     PID: $(pgrep -x "$APP_NAME" | head -1) — will spawn a fresh instance below."
else
    echo "  ✅ $APP_NAME stopped"
fi

# ─── Step 2: (optional) wipe DerivedData ────────────────────────────
if ! $FAST; then
    echo ""
    echo "→ Step 2/5: wiping DerivedData (use --fast to skip)"
    rm -rf $DERIVED_GLOB
    echo "  ✅ DerivedData cleared"
else
    echo ""
    echo "→ Step 2/5: --fast set, skipping DerivedData wipe"
fi

# ─── Step 3: Regenerate + build ────────────────────────────────────
echo ""
echo "→ Step 3/5: regenerating Xcode project + building (Debug, arm64)"
if ! $FAST; then
    rm -rf "${APP_NAME}.xcodeproj"
fi
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate 2>&1 | sed 's/^/  /'
fi
xcodebuild build \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" \
    -quiet 2>&1 | tail -3 | sed 's/^/  /'
echo "  ✅ build OK"

# Resolve the freshly-built .app path (avoid the Index.noindex variant).
APP_PATH="$(find $DERIVED_GLOB/Build/Products/Debug -maxdepth 2 -type d -name "${APP_NAME}.app" 2>/dev/null | head -1)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "  ❌ Could not locate built .app under DerivedData" >&2
    exit 1
fi
echo "  ✅ App bundle: $APP_PATH"

# Sanity: confirm the binary is signed by our local cert (catches the
# regression where someone reverts project.yml back to ad-hoc).
# Note: `|| true` guards against SIGPIPE when grep -m1 closes the pipe
# while codesign is still writing.
SIGNER="$(codesign -dvvv "$APP_PATH" 2>&1 | grep 'Authority=' | head -1 | cut -d= -f2)" || true
echo "  ✅ Signed by: ${SIGNER:-<unknown>}"
if [[ "$SIGNER" != *"GoodRecording Local Dev"* && "$SIGNER" != *"Apple Development"* && "$SIGNER" != *"Developer ID"* ]]; then
    echo ""
    echo "  ⚠️  Build is using ad-hoc signing! TCC will silently reject." >&2
    echo "     Run scripts/make-local-cert.sh first." >&2
    exit 1
fi

# ─── Step 4: TCC reset + UserDefaults cleanup + cfprefsd reset ─────
echo ""
echo "→ Step 4/5: clearing TCC + sandbox UserDefaults + cfprefsd cache"
tccutil reset ScreenCapture "$BUNDLE_ID" 2>&1 | sed 's/^/  /'
tccutil reset Microphone   "$BUNDLE_ID" 2>&1 | sed 's/^/  /'

# Clear stale sandbox UserDefaults entries that may carry forward old
# preset values (e.g. .sysOnly from an older quick-fix). `defaults
# delete` doesn't work for sandboxed apps because it targets the
# user-domain plist, not the sandbox container — so we reach into the
# container plist directly.
SANDBOX_PLIST="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Preferences/$BUNDLE_ID.plist"
if [[ -f "$SANDBOX_PLIST" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :good.recording.preset.lastUsed.v1" "$SANDBOX_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :good.recording.settings.v1"        "$SANDBOX_PLIST" 2>/dev/null || true
    echo "  ✅ Sandbox UserDefaults cleared (preset + settings)"
fi

killall -u "$USER" cfprefsd 2>/dev/null || true
sleep 1
echo "  ✅ TCC + cfprefsd reset (next launch will show native dialog)"

# ─── Step 5: Launch ────────────────────────────────────────────────
echo ""
echo "→ Step 5/5: launching $APP_NAME (forcing a new instance with -n)"
# -n forces a brand-new instance even if a zombie is already running.
open -n "$APP_PATH"
sleep 2
NEW_PIDS="$(pgrep -x "$APP_NAME" | tr '\n' ' ')"
echo "  ✅ Launched (PID(s): ${NEW_PIDS:-?})"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " ✅ Rebuilt + relaunched"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " Next steps in the app:"
echo "   1. Click 开始录制"
echo "   2. macOS will show the native Screen Recording dialog —"
echo "      click \"打开系统设置\""
echo "   3. In Privacy → Screen Recording, ensure GoodRecording"
echo "      is on (it should be added + checked automatically)"
echo "   4. macOS asks \"Quit and Reopen\" — accept"
echo "   5. After auto-relaunch, click 开始录制 again — recording"
echo "      should start immediately"
echo ""
echo " Tail the log to verify:"
echo "   tail -f ~/Library/Containers/$BUNDLE_ID/Data/Library/Logs/$APP_NAME/\$(date +%Y-%m-%d).log"
echo ""
