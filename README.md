# good-recording

A local-first macOS screen + audio recording client.
Min macOS 15 (Sequoia), Universal Binary (arm64 + x86_64), App Sandboxed,
no network at runtime.

> **Spec & design lives elsewhere.** This repository contains *only* the
> implementation. The canonical spec, plan, and tasks for v1 live in the
> sibling `home-spec` repository under
> `specs/001-good-recording/` (branch `001-good-recording`):
>
> - `spec.md` — feature spec + acceptance criteria
> - `plan.md` — implementation plan + Constitution Check
> - `research.md` — tech decisions
> - `data-model.md` — entities & state machines
> - `contracts/` — UI surfaces / output files / permissions / logs contracts
> - `quickstart.md` — dev build/run/test guide (the source of truth for what
>   the scripts in this repo do)
> - `tasks.md` — full 118-task implementation checklist
>
> Always cross-reference `specs/001-good-recording/` in `home-spec` before
> changing anything in this repo's `Sources/` or `scripts/`.

---

## Status

Phase 1 (Setup) skeleton — `tasks.md` T001–T012 complete. The project
compiles to an empty SwiftUI window placeholder; subsequent phases (Core
modules, Features US1–US5, Polish) populate `Sources/Core/*` and
`Sources/Features/US{N}-*/`.

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| macOS | 15.0+ | Min deployment target |
| Xcode | 16.0+ | Swift 6 toolchain |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | latest | Materializes `GoodRecording.xcodeproj` from `project.yml`. Install: `brew install xcodegen` |

## Build / Run

```bash
# 1. Generate the Xcode project (re-run any time project.yml changes)
xcodegen generate

# 2. Open in Xcode
open GoodRecording.xcodeproj

# 3. Or build a Universal Binary from the command line
./scripts/build-universal.sh

# 4. Sign + notarize for distribution (requires Developer ID + notarytool profile)
./scripts/sign-and-notarize.sh build/Release/GoodRecording.app
```

## CI lint suite

All lint scripts live under `scripts/ci/`:

| Script | Purpose | Stage |
|---|---|---|
| `check-entitlements.sh` | Constitution I — reject network / sandbox-escape entitlements | T010 — implemented now |
| `xc-dependency-lint.sh` | Constitution III — reject cross-feature module imports | T012 — implemented now |
| `check-no-network.sh` | SC-006 — assert zero outbound network during recording | T010 stub → full T114 |
| `check-strings.sh` | Constitution II — reject tech jargon in user-facing strings | T010 — implemented now |
| `check-logs-contract.sh` | `contracts/logs.md` — validate JSON Lines schema | T010 stub → full alongside T016 |

## Layout

```text
.
├── project.yml                    # XcodeGen source of truth
├── Sources/
│   ├── App/                       # @main, AppDelegate, FeatureFlags
│   ├── Features/                  # One subdir per user story (US1..US5)
│   └── Core/                      # Shared services (Capture, Encoding, Storage,
│                                  #   Permissions, Hotkey, Notifications, Logging)
├── Resources/                     # Info.plist, .entitlements, Assets, Localizable
├── Tests/                         # UnitTests, IntegrationTests, UITests
└── scripts/
    ├── build-universal.sh
    ├── sign-and-notarize.sh
    ├── ExportOptions.plist
    └── ci/                        # Constitution + SC verification scripts
```

## License

TBD.
