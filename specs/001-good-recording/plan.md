# Implementation Plan: good-recording (macOS 屏幕与音频录制工具)

**Branch**: `001-good-recording` | **Date**: 2026-05-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-good-recording/spec.md`

## Summary

good-recording 是一款本地优先的 macOS 屏幕与音频录制客户端。v1 提供
单一的"开始/停止"主交互、支持全屏 / 单窗口 / 自定义区域三种录制范围、
独立开关的环境音 / 系统音、可配置的分辨率与容器格式，以及"仅录音"
模式；任意时刻通过主窗口按钮、菜单栏状态项或全局快捷键 `⌃⇧K` 都可
立即停止并将文件持久化到本地。

技术上选择 Apple 原生栈（Swift 6 + SwiftUI/AppKit 混合 +
ScreenCaptureKit + AVFoundation），最低部署目标 macOS 15 (Sequoia)，
打包 Universal Binary（arm64 + x86_64），全程在 App Sandbox 内运行，
不引入任何网络或第三方音频驱动依赖。所有数据（录制文件、设置、日志）
均落在用户本地。

## Technical Context

**Language/Version**: Swift 6.0（启用 strict concurrency；`@MainActor`/
actor isolation 与 ScreenCaptureKit 的 `AsyncSequence` 流式 API 天然契合）

**Primary Dependencies**:

- **ScreenCaptureKit** (Apple, macOS 12.3+，在 15 上为成熟版本) — 屏幕
  与系统音原生采集；通过 `SCContentFilter` / `SCStreamConfiguration`
  配置全屏 / 窗口 / 区域；通过 `SCStreamConfiguration.capturesAudio = true`
  + `excludesCurrentProcessAudio` 实现系统音录制。
- **AVFoundation** — 麦克风采集（`AVCaptureSession`）、视频/音频编码
  封装（`AVAssetWriter` + VideoToolbox 硬件加速）、音轨混音
  （`AVMutableAudioMix` / `AVAudioMixerNode`）。
- **SwiftUI + AppKit** — SwiftUI 负责绝大多数视图；AppKit 负责需要
  原生能力的部分（菜单栏 `NSStatusItem`、区域选取的全屏 overlay
  `NSPanel`、文件选择器）。
- **Carbon `RegisterEventHotKey`** — 全局快捷键 `⌃⇧K`（无需辅助功能
  权限，是 macOS 上注册系统级 hotkey 最轻量的标准路径）。
- **UserNotifications** — "已保存" / 异常停止 / 快捷键冲突等通知。
- **OSLog + 自建 JSON Lines logger** — 结构化本地日志，落到沙箱
  Library/Logs。

**Storage**:

- **录制文件**：默认 `~/Movies/Good Recording/` （需要
  `com.apple.security.assets.movies.read-write` entitlement）；用户
  自定义目录通过 `NSOpenPanel` + Security-Scoped Bookmark 持久化。
- **设置**：`UserDefaults`（沙箱内自动落到
  `~/Library/Containers/<bundle-id>/Data/Library/Preferences/`）。
- **日志**：JSON Lines，落在
  `~/Library/Containers/<bundle-id>/Data/Library/Logs/GoodRecording/`，
  应用菜单 "查看日志" 可一键打开该目录。
- **Security-Scoped Bookmarks**：用户选择的自定义保存目录以
  app-scope bookmark 形式存入 `UserDefaults`，跨重启可继续访问。

**Testing**:

- **Swift Testing**（Swift 6 macro 框架）+ **XCTest**（兼容旧路径，
  必要时混用）— 单元测试。
- **XCUITest** — 主流程 UI 烟雾、可访问性 (Accessibility Inspector
  脚本化) 检查。
- **手工集成测试 + CI 半自动化**：ScreenCaptureKit 因为需要 TCC
  授权，自动化覆盖度受限；用 macOS VM (一次性预授权快照) 跑
  端到端验收脚本。
- **Performance**：Instruments + `XCTMetric`（启动时间、内存峰值），
  对应 SC-008 / SC-009 / SC-010 阈值。

**Target Platform**: macOS 15.0 (Sequoia) 及以上；Apple Silicon (arm64)
+ Intel (x86_64) Universal Binary。

**Project Type**: macOS desktop-app (单一 app target + 测试 target；
所有 Feature 模块以 SPM in-project local packages 形式组织以隔离
US 边界)。

**Performance Goals**:

- 冷启动 → 主界面可交互 ≤ 2.0 s（Apple Silicon，SC-008）
- 主交互（按下"开始"→ UI 反馈"录制中"）p95 ≤ 100 ms（SC-010）
- 停止录制 → Finder 可见可播放文件 ≤ 3 s（≤10 min 录制，SC-003）
- 1080p + 双音轨录制 30 min 后 100% 可被 QuickTime 完整播放（SC-004）

**Constraints**:

- App Sandbox 强制开启；Hardened Runtime + Developer ID 签名 + 公证。
- 默认配置下零网络出站请求（SC-006）；不引入 Sparkle、Crashlytics、
  Firebase 等任何带遥测能力的第三方 SDK。
- 空闲常驻内存 ≤ 200 MB；录制中峰值 ≤ 500 MB（SC-009）。
- 仅使用 Apple 第一方 framework；不依赖 BlackHole / Loopback 等
  虚拟音频驱动（macOS 15 的 SCK 已原生支持系统音）。
- Universal Binary：CI 必须同时构建并测试 arm64 与 x86_64。

**Scale/Scope**:

- 单用户桌面 App；无多用户/协作概念。
- 5 个 user stories、29 个 functional requirements、3 个核心实体。
- v1 估计 ~6–10K 行 Swift；约 6 个主要可见界面（主窗口、区域选取
  overlay、窗口选取列表、设置、关于、菜单栏菜单）+ 1 个全局快捷键。
- 单文件录制：v1 不强制最大时长上限；超过容器单文件 4 GB 限制时
  自动启动新分段（详见 spec edge case）。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.
Source of truth: `.specify/memory/constitution.md` (current version 1.0.0).*

For each gate, mark PASS / FAIL / N/A and link to the spec / design section
that justifies the answer. Any FAIL MUST be either resolved before continuing
or recorded in the "Complexity Tracking" table below with a rejected simpler
alternative.

### Initial Constitution Check (pre-Phase 0)

- [x] **I. 本地优先与隐私保护 (NON-NEGOTIABLE)** — **PASS**.
      所有依赖均为 Apple 第一方本地 framework，零网络出站；遥测默认关闭
      （根本就不存在）；权限申请均在 UI 中显式说明用途。证据：spec
      FR-025 / FR-026、SC-006；本计划"Primary Dependencies"无任何
      网络/分析/远端服务。
- [x] **II. 普通用户为中心的简洁体验** — **PASS**.
      US1 主路径 ≤ 3 步（启动 → 选范围（默认全屏可跳过）→ 点开始）；
      单一主按钮（FR-001）；全局快捷键有 tooltip 自描述（FR-028）；
      所有错误消息走"发生了什么/原因/下一步"三要素（spec II 章节）。
      不向用户暴露 `JSON`/`path`/`endpoint` 等技术词。
- [x] **III. 独立可测与渐进交付 (NON-NEGOTIABLE)** — **PASS**.
      源码按 5 个 US 切成独立 SPM 子模块（见 Project Structure），
      每个模块能独立编译 + 独立测试；Feature flag 通过编译时
      `#if FEATURE_xxx` + 运行时 `FeatureFlags.swift` 双层控制；MVP
      仅启用 US1，US2–US5 独立开关。每个 US 都有 Independent Test。
- [x] **IV. macOS 原生与平台一致性** — **PASS**.
      纯 SwiftUI + AppKit + Apple framework，HIG 默认满足（菜单栏、
      快捷键、深色模式、VoiceOver、Retina）；min macOS = 15
      （current 假设为 16，"current − 1"，满足"current − 2"的 SHOULD
      策略）；CI 输出 Universal Binary；通过 Sandbox + Hardened
      Runtime + 公证。本决定 close 宪法
      `TODO(MIN_MACOS_VERSION) → macOS 15.0`。
- [x] **V. 本地可观测与可恢复** — **PASS**.
      OSLog + 自建 JSON Lines logger 落到沙箱 Library/Logs；应用菜单
      提供"查看日志"/"导出日志"/"清空日志"；录制文件本身就是
      用户可携带的标准 mp4/m4a，永不锁死；FR-016「恢复默认设置」前
      二次确认；崩溃报告本地优先（不接入第三方 crashlytics）。v1
      不承诺非正常终止下的录制可恢复（已在 spec Clarifications #3
      显式记录），不视为违反原则——原则要求的是"用户可恢复"，
      指的是数据层面的可携带与可备份，已通过文件可导出兑现。
- [x] **macOS Platform Constraints** — **PASS**.
      Cold start / RSS / 交互延迟目标全部对齐（SC-008 / 009 / 010）；
      数据存储位置全部位于沙箱 Application Support /
      `~/Movies/Good Recording/` / 用户显式选择目录；CI 矩阵
      `arch in [arm64, x86_64]` 同时构建 + 跑测试。

**Initial gate result**: 6/6 PASS — proceed to Phase 0.

### Post-Design Constitution Re-check (after Phase 1)

- [x] **I. 本地优先** — **PASS**. `contracts/permissions.md` 列出的
      所有权限申请均为本地资源访问；`contracts/output-files.md` 限定
      文件落地点；`contracts/logs.md` 不含任何远端 sink。
- [x] **II. 普通用户简洁体验** — **PASS**. `contracts/ui-surfaces.md`
      限定 v1 仅 6 个可见界面；主窗口仅 1 个核心 CTA；新增 hotkey
      可发现性走 tooltip。
- [x] **III. 独立可测与渐进交付** — **PASS**. `Project Structure`
      章节按 US 切包；`data-model.md` 的实体不在 US 之间产生硬绑定。
- [x] **IV. macOS 原生** — **PASS**. 无新增第三方依赖；entitlements
      固定为最小集（见 contracts/permissions.md）。
- [x] **V. 本地可观测与可恢复** — **PASS**. `contracts/logs.md`
      明确 schema 与轮转策略；`contracts/output-files.md` 明确文件
      命名与位置以保证可被用户/其它工具再处理。
- [x] **macOS Platform Constraints** — **PASS**. 性能目标均纳入
      `quickstart.md` 的 verify 步骤。

**Post-design gate result**: 6/6 PASS — proceed to `/speckit-tasks`。

## Project Structure

### Documentation (this feature)

```text
specs/001-good-recording/
├── plan.md                      # This file (/speckit-plan output)
├── spec.md                      # Feature spec (from /speckit-specify + /speckit-clarify)
├── research.md                  # Phase 0 — tech decisions + alternatives
├── data-model.md                # Phase 1 — entities & state machines
├── contracts/                   # Phase 1 — interface contracts
│   ├── ui-surfaces.md           # Screens, states, transitions
│   ├── output-files.md          # File format / naming / location
│   ├── permissions.md           # TCC + entitlement flows
│   └── logs.md                  # Local log schema
├── quickstart.md                # Phase 1 — dev build/run/test guide
├── checklists/
│   └── requirements.md          # Spec quality checklist (from /speckit-specify)
└── tasks.md                     # Phase 2 (created by /speckit-tasks, NOT here)
```

### Source Code (repository root)

```text
apps/good-recording/                 # macOS app target (Xcode project)
├── GoodRecording.xcodeproj/
├── Sources/
│   ├── App/                         # @main, AppDelegate, RootView, FeatureFlags
│   ├── Features/                    # One SPM-local module per user story
│   │   ├── US1-Recording/           # Core start/stop/save loop (P1 MVP)
│   │   ├── US2-ScopeSelection/      # Full-screen / window / region picker (P2)
│   │   ├── US3-AudioSources/        # Mic + system audio mixing toggles (P2)
│   │   ├── US4-QualitySettings/     # Resolution / format / persistence (P3)
│   │   └── US5-AudioOnlyMode/       # Audio-only mode shell (P3)
│   └── Core/                        # Cross-cutting services (no US dependency)
│       ├── Capture/                 # ScreenCaptureKit + AVFoundation wrappers
│       ├── Encoding/                # AVAssetWriter pipeline (mp4 / mov / m4a)
│       ├── Storage/                 # Save location, file naming, bookmarks
│       ├── Permissions/             # TCC helpers (Screen / Mic / Notifications)
│       ├── Hotkey/                  # Carbon RegisterEventHotKey wrapper
│       ├── Notifications/           # UserNotifications wrappers
│       └── Logging/                 # JSON Lines + OSLog
├── Resources/
│   ├── Assets.xcassets/             # Icon, accent color
│   ├── GoodRecording.entitlements   # Sandbox + minimum entitlement set
│   ├── Info.plist                   # Min OS, NSUsageDescription strings
│   └── Localizable.xcstrings        # zh-Hans + en
└── Tests/
    ├── UnitTests/                   # Per-module unit tests (Swift Testing)
    ├── IntegrationTests/            # End-to-end via TCC-pre-authorized VM snapshot
    └── UITests/                     # XCUITest smoke + Accessibility Inspector script

scripts/
├── build-universal.sh               # arm64 + x86_64 → .app bundle
├── sign-and-notarize.sh             # codesign + notarytool + stapler
└── ci/                              # GitHub Actions config
```

**Structure Decision**: 选择 **macOS desktop-app** 单一 Xcode 工程 +
in-project SPM local packages 的混合布局。
- 工程在 `apps/good-recording/`，给后续可能新增的兄弟应用（例如
  `apps/good-recording-helper/` 录屏伴侣 / 上传助手）留出 monorepo
  扩展位。
- `Sources/Features/US{N}-...` 一个 US 一个本地 SPM 包，强制独立
  可测与可独立 disable（直接对齐宪法 III）；`Sources/Core/*` 是被
  所有 Features 共用的服务，遵循"Core 不依赖 Features"的单向依赖
  规则。
- 测试 target 拆 Unit / Integration / UI 三档，对齐宪法 III 的
  "TDD 红 → 绿 → 重构"以及 NON-NEGOTIABLE 原则相关的 acceptance
  test 要求。

## Complexity Tracking

> Constitution Check 全部 PASS，无需填写。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| —         | —          | —                                    |
