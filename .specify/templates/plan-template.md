# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: [e.g., Python 3.11, Swift 5.9, Rust 1.75 or NEEDS CLARIFICATION]  
**Primary Dependencies**: [e.g., FastAPI, UIKit, LLVM or NEEDS CLARIFICATION]  
**Storage**: [if applicable, e.g., PostgreSQL, CoreData, files or N/A]  
**Testing**: [e.g., pytest, XCTest, cargo test or NEEDS CLARIFICATION]  
**Target Platform**: [e.g., Linux server, iOS 15+, WASM or NEEDS CLARIFICATION]
**Project Type**: [e.g., library/cli/web-service/mobile-app/compiler/desktop-app or NEEDS CLARIFICATION]  
**Performance Goals**: [domain-specific, e.g., 1000 req/s, 10k lines/sec, 60 fps or NEEDS CLARIFICATION]  
**Constraints**: [domain-specific, e.g., <200ms p95, <100MB memory, offline-capable or NEEDS CLARIFICATION]  
**Scale/Scope**: [domain-specific, e.g., 10k users, 1M LOC, 50 screens or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.
Source of truth: `.specify/memory/constitution.md` (current version 1.0.0).*

For each gate, mark PASS / FAIL / N/A and link to the spec / design section
that justifies the answer. Any FAIL MUST be either resolved before continuing
or recorded in the "Complexity Tracking" table below with a rejected simpler
alternative.

- [ ] **I. 本地优先与隐私保护 (NON-NEGOTIABLE)**: All user data stays on
      device. Any network call has explicit UI disclosure, an offline fallback,
      and is auditable in local logs. Telemetry defaults OFF.
- [ ] **II. 普通用户为中心的简洁体验**: Main path ≤ 3 steps; copy uses
      everyday language (no `JSON`/`path`/`endpoint` leaking to users); every
      reversible action is undoable; every irreversible action has a confirm
      dialog with consequences spelled out.
- [ ] **III. 独立可测与渐进交付 (NON-NEGOTIABLE)**: Each user story has its
      own automated unit + acceptance test, ships behind a flag / module
      boundary, and is deliverable as MVP → gradual rollout → GA with explicit
      exit criteria per stage.
- [ ] **IV. macOS 原生与平台一致性**: App passes Sandbox + Hardened Runtime
      + Notarization; UI follows Apple HIG (menu bar, shortcuts, dark mode,
      VoiceOver); ships Universal Binary; minimum macOS version recorded and
      within "current − 2 majors".
- [ ] **V. 本地可观测与可恢复**: Critical operations emit structured local
      logs (user-visible, exportable, clearable); user data is exportable in
      a plain-text format; destructive changes auto-snapshot; crash reports
      are local-first.
- [ ] **macOS Platform Constraints**: Cold start ≤ 2.0s, idle RSS ≤ 200 MB,
      interaction ≤ 100 ms p95 on Apple Silicon; data stored only in
      sandboxed `Application Support` / user-selected paths; CI builds &
      tests both arm64 and x86_64.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
