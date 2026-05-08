# Troubleshooting & Dev Environment Lessons

**Feature**: 001-good-recording
**Last updated**: 2026-05-08
**Audience**: anyone setting up the implementation repo
(`~/project/good-recording/`) on a fresh macOS 26 dev machine.

This document is the lived-experience companion to
[`quickstart.md`](./quickstart.md). `quickstart.md` tells you the
*happy path*; this file tells you the *trapdoors* — every issue we
hit at least once during the v0.1 buildout, with root cause and
exact fix.

If you hit something not listed here, please add it (with timestamp,
symptom, root cause, fix).

---

## Issue 0 — TL;DR fresh-machine setup recipe

1. Install full Xcode (16.0+) from the App Store. Confirm with
   `xcode-select -p` pointing at `/Applications/Xcode.app/...`. If
   not, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
   then `sudo xcodebuild -license accept`.
2. `brew install xcodegen`.
3. `cd ~/project/good-recording && ./scripts/setup-xcode.sh` —
   one-shot Xcode setup + smoke build.
4. `./scripts/make-local-cert.sh` — creates a stable self-signed
   code-signing identity. You'll need to enter your **macOS login
   password** (= keychain password) and **sudo password** at the
   right prompts. They're typically the same password.
5. `./scripts/rebuild-and-reauth.sh` — every time you change Swift
   code and need to re-grant Screen Recording permission, this is
   the one-stop. (See Issue 5 for why every rebuild requires it.)

If any of those scripts fail, find the matching issue below.

---

## Issue 1 — `xcodebuild` reports "tool requires Xcode but active developer directory is a command line tools instance"

**Symptom**

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active
developer directory '/Library/Developer/CommandLineTools' is a
command line tools instance
```

**Root cause**: full Xcode is not installed, OR `xcode-select` still
points at Command Line Tools (CLT). CLT alone provides `clang` and
`swift` but **not** `xcodebuild` / `notarytool` / `stapler` /
SwiftUI runtime.

**Fix**:

```bash
# 1. Install full Xcode (App Store recommended, ~10 GB)
# 2. Switch xcode-select pointer
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# 3. Accept license
sudo xcodebuild -license accept
# 4. Verify
xcodebuild -version    # should print Xcode 16.x or 26.x
```

We've baked a pre-flight check into both
`scripts/build-universal.sh` and `scripts/sign-and-notarize.sh` so
you'll see the friendly Chinese error message instead of the
opaque `xcode-select` one.

---

## Issue 2 — XcodeGen overwrites `Info.plist` and `.entitlements`

**Symptom**: after running `xcodegen generate`, your
`Resources/Info.plist` becomes a tiny stub and
`Resources/GoodRecording.entitlements` becomes `<dict/>` — all your
NSUsageDescription strings + entitlement keys disappear.

**Root cause**: XcodeGen's `info:` and `entitlements:` keys in
`project.yml` cause it to *regenerate* those files from the YAML on
every `xcodegen generate` run. Anything not restated in the YAML is
silently dropped.

**Fix**: never use `info:` / `entitlements:` keys. Reference the
files via build settings instead:

```yaml
targets:
  GoodRecording:
    settings:
      base:
        INFOPLIST_FILE: Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: Resources/GoodRecording.entitlements
```

This way XcodeGen only *references* the files; you own the truth.

---

## Issue 3 — AssetWriter "acceptance gate" rejects perfectly good recordings

**Symptom**: every recording stops cleanly but the file lands in
`~/Movies/Good Recording/_failed/<uuid>.mp4` instead of the proper
timestamped name. `mdls` confirms the quarantined file is a valid
mp4 with non-zero duration.

**Root cause**: in
`Sources/Core/Encoding/AssetWriterPipeline.swift::finishWriting()`,
we ran the `AVURLAsset(url:)` track-count + duration validation
on the temp file (`tmp/recording-{id}.mp4.partial`) **before**
moving it to the final location. AVURLAsset's UTI sniffing rejects
the unknown `.partial` extension and reports zero tracks even on a
perfectly fine file.

**Fix**: move tmp → final FIRST, then run acceptance gate on the
final URL (which has a recognised `.mp4` / `.mov` / `.m4a`
extension). Already in the codebase as of commit `0c29d78`.

**Recovering files from `_failed/`**: they're real recordings, just
mislabeled — `mv ~/Movies/"Good Recording"/_failed/*.mp4
~/Movies/"Good Recording"/` and they play.

---

## Issue 4 — App is silently rejected from Screen Recording in macOS 26

**Symptom**: app starts, you click 开始录制, you grant Screen
Recording permission in System Settings, the toggle stays on, but
every subsequent click of 开始录制 still shows our in-app permission
card. Logs show `permission_check status=denied` over and over.

**Root cause**: macOS 26 silently denies ScreenCaptureKit (and other
TCC-gated capabilities) to **ad-hoc-signed** sandboxed apps.
Specifically:

- Ad-hoc signing means `Signature=adhoc` and
  `TeamIdentifier=not set`.
- TCC under macOS 26 + Hardened Runtime only grants Screen Recording
  to apps with a *stable signing identity*. With ad-hoc signing,
  the binary's `cdhash` changes on every rebuild, and TCC can't
  pin authorization to a stable identity.
- Result: TCC's `CGRequestScreenCaptureAccess()` returns `false`
  immediately and never even shows the system dialog. The app is
  in a no-grant-possible state.

**Fix (the proper one)**: sign every build with a stable identity.
We use a local self-signed certificate (free, no Apple Developer
account needed) created by `scripts/make-local-cert.sh`. See Issue 6
for what could go wrong while creating that cert.

**Why not just "open System Settings and add the app manually"?**
You can — but every rebuild changes the cdhash, and without a
stable signing identity TCC treats it as a brand-new app the next
launch. Stable signing solves the cdhash drift.

---

## Issue 5 — Even with stable signing, every rebuild needs a re-grant

**Symptom**: `make-local-cert.sh` finished successfully, you signed
your build with `GoodRecording Local Dev`, you granted Screen
Recording permission once. App works. Later you change one Swift
file, rebuild, launch the new build — back to "permission denied"
state.

**Root cause**: a self-signed cert has no Apple Team Identifier,
so TCC falls back to `cdhash`-based identification. Every rebuild
changes the binary content → changes cdhash → TCC treats it as a
new app instance → stored authorization doesn't apply.

The only true cure is signing with an Apple-issued identity that
carries a stable Team Identifier (Apple Developer ID at $99/year, or
the free Apple Personal Team certificate via Xcode → Settings →
Accounts). See [Apple's documentation on Team IDs and TCC](https://developer.apple.com/documentation/security/transparency-consent-control).

**Workaround for v0.1 dev builds**: `./scripts/rebuild-and-reauth.sh`
runs `tccutil reset ScreenCapture com.zzming.good-recording` on
every rebuild. That clears the stale TCC entry, so the *next* launch
of the freshly-built app shows the macOS native dialog and you
re-grant in 5 seconds. Annoying but bounded.

---

## Issue 6 — `errSecInternalComponent` during codesign step

**Symptom**: `xcodebuild build` fails at the CodeSign step with
exactly:

```text
errSecInternalComponent
Command CodeSign failed with a nonzero exit code
```

**Root cause**: `make-local-cert.sh` created the cert + private key
correctly, but couldn't grant codesign permission to access the key
because the keychain wasn't unlocked (you didn't enter your macOS
login password during Step 3).

**Fix**: re-run with the password prompt:

```bash
read -s -p "macOS login password: " PASS && echo && \
security unlock-keychain -p "$PASS" ~/Library/Keychains/login.keychain-db && \
security set-key-partition-list \
    -S apple-tool:,apple:,codesign:,unsigned: \
    -s -k "$PASS" ~/Library/Keychains/login.keychain-db && \
unset PASS && echo "✅ Keychain ACL fixed"
```

`make-local-cert.sh` since commit `952fd12` prompts for the password
correctly during Step 3, so re-running the script fresh also works.

---

## Issue 7 — App crashes immediately on launch with "different Team IDs"

**Symptom**: app launches and crashes within milliseconds. Crash
log under `~/Library/Logs/DiagnosticReports/GoodRecording-*.ips`
contains:

```text
Termination Reason: Library missing
Library not loaded: @rpath/GoodRecording.debug.dylib
Reason: '...' (code signature in '...GoodRecording.debug.dylib' not
valid for use in process: mapping process and mapped file (non-platform)
have different Team IDs)
```

**Root cause**: Xcode 16+ defaults `ENABLE_DEBUG_DYLIB = YES` for
Debug builds, splitting the Swift portion into a separate
`<App>.debug.dylib` for faster incremental compiles. Modern dyld
under Hardened Runtime checks Team ID equivalence between the main
binary and its companion dylibs. With self-signed certs (no team
ID on either side), dyld treats `team_id="not set"` on both as a
mismatch and bails.

**Fix**: in `project.yml`:

```yaml
configs:
  Debug:
    ENABLE_HARDENED_RUNTIME: NO
    ENABLE_DEBUG_DYLIB: NO
  Release:
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_DEBUG_DYLIB: NO
```

Already in `project.yml` since commit `c5c2ea4`. Note both Debug and
Release set `ENABLE_DEBUG_DYLIB = NO` because the .debug.dylib
optimization isn't worth the complexity for a project this size.

**If you still see the crash**: you probably ran `xcodebuild` from
inside an open Xcode (Xcode caches the old `.xcodeproj`). Close
Xcode (⌘Q), then `rm -rf GoodRecording.xcodeproj &&
xcodegen generate`, then rebuild from the command line.

---

## Issue 8 — UserDefaults changes don't take effect after `defaults delete`

**Symptom**: you run `defaults delete com.zzming.good-recording <key>`
to clear a stored preset, but next app launch the preset is still
the old value.

**Root cause**: macOS 26 caches sandboxed-app UserDefaults in the
`cfprefsd` daemon. Direct `defaults` writes don't always invalidate
the cache immediately.

**Fix**:

```bash
killall -u $USER cfprefsd
```

then re-launch the app. `cfprefsd` re-reads from disk on the next
preferences request.

For sandboxed apps, the actual plist lives at:

```text
~/Library/Containers/com.zzming.good-recording/Data/Library/Preferences/com.zzming.good-recording.plist
```

You can also edit it directly with `plutil -p` to inspect or
`/usr/libexec/PlistBuddy -c "Delete :<key>" <path>` to remove keys.

---

## Issue 9 — Recording sounds like "电音" (electronic distortion)

**Symptom**: recording is technically successful (file plays in
QuickTime, video looks fine) but the audio track is robotic /
glitchy / cyclically chopped.

**Root cause**: in v0.1's `AudioMixer.flushIfReady()`, when both
mic and system audio sources are enabled, the mixer paired buffers
1-to-1 and dropped any unpaired pending buffer when the next one of
the same source arrived. Mic and system audio arrive at different
rates (mic ~44.1 kHz vs system 48 kHz, with different buffer
chunking), so this caused most system audio buffers to be silently
overwritten while waiting for a mic match → the AssetWriter received
discontinuous PCM samples → playback sounded glitchy.

**Fix in v0.1** (commit `44fee3d`): pass system audio straight
through, drop mic when both are enabled. Single-source mode
(only mic OR only system) bypasses the mixer entirely and is
bit-exact. See `Sources/Core/Encoding/AudioMixer.swift` v0.1
LIMITATION comment.

**Fix in v0.2** (planned): rewrite `AudioMixer` using
`AVAudioEngine` + `AVAudioConverter` so two streams of different
formats are first normalized to a common Float32 stereo 48 kHz
format, then mixed sample-aligned by timestamp. This honors spec
FR-011 properly (two sources → single mixed AAC track).

**Workaround for v0.1**: default `RecordingPreset.factoryDefault`
is `.sysOnly` so users get clean system audio out of the box.
Phase 5 (US3) will introduce a UI toggle to switch to mic-only or
back to both.

---

## Issue 10 — Xcode UI run (⌘R) uses cached `.xcodeproj` ignoring recent `project.yml` changes

**Symptom**: you change `project.yml`, then ⌘R in Xcode, but the
build doesn't reflect your new build settings (e.g. you set
`ENABLE_DEBUG_DYLIB: NO` but the .debug.dylib is still produced).

**Root cause**: Xcode caches the open `.xcodeproj` in memory; it
doesn't re-read `project.yml` automatically. Re-running
`xcodegen generate` from a terminal *while Xcode is open* may also
fail or produce inconsistent results because Xcode holds locks on
the project file.

**Fix**: `⌘Q` to fully quit Xcode, then from a terminal:

```bash
rm -rf GoodRecording.xcodeproj    # so xcodegen rebuilds from scratch
xcodegen generate
xcodebuild build ...              # build from CLI to verify
open GoodRecording.xcodeproj      # only after CLI build succeeds
```

After this, in-Xcode ⌘R will use the regenerated project.

---

## Issue 11 — `pkill` / `kill -9` can't kill the running app

**Symptom**: `pkill -x GoodRecording` returns 0 and reports success,
but `pgrep GoodRecording` still shows the same PID. Even
`kill -9 <pid>` doesn't stop it.

**Root cause**: when launched by `open` or by Xcode, the app's
parent process (`launchd` or the Xcode debugger) auto-restarts it
on signal. Direct kills bounce.

**Fix**:

- From the GUI: ⌘Q in the app, or right-click in Dock → 退出
- From CLI: `osascript -e 'tell application "GoodRecording" to quit'`
- Nuclear: `launchctl bootout gui/$(id -u) <plist-path>` (advanced)

---

## How to gather diagnostics when something else breaks

```bash
# 1. App's own structured log
tail -50 ~/Library/Containers/com.zzming.good-recording/Data/Library/Logs/GoodRecording/$(date +%Y-%m-%d).log

# 2. Latest crash report
ls -t ~/Library/Logs/DiagnosticReports/GoodRecording* | head -1 | xargs cat

# 3. Current signing identity
codesign -dvvv ~/Library/Developer/Xcode/DerivedData/GoodRecording-*/Build/Products/Debug/GoodRecording.app 2>&1 | head -15

# 4. Available code-signing identities in keychain
security find-identity -v -p codesigning

# 5. TCC system log for our app
log show --info --last 5m --predicate 'subsystem == "com.apple.TCC"' 2>&1 | grep -iE "(good-recording|com.zzming)"

# 6. Sandbox preferences plist
plutil -p ~/Library/Containers/com.zzming.good-recording/Data/Library/Preferences/com.zzming.good-recording.plist
```

If you find a new failure mode not covered here, please add a
new `Issue N` section above with:

1. **Symptom** (the exact error message you saw or the user-visible behavior)
2. **Root cause** (one paragraph, plain language)
3. **Fix** (the exact commands or code change that resolved it)

This file is the most valuable artifact in the repo for future-me
and future-collaborators. Keep it current.
