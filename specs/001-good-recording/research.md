# Phase 0 Research: good-recording

**Feature**: 001-good-recording
**Date**: 2026-05-07
**Source**: [plan.md](./plan.md) — Technical Context section

This document records the technical decisions made before starting design,
along with the alternatives considered and the rationale for each pick. The
goal is to leave Phase 1 (`data-model.md` / `contracts/` / `quickstart.md`)
with **zero `NEEDS CLARIFICATION` markers**.

---

## R1 — Screen + system audio capture path

**Decision**: 使用 **ScreenCaptureKit (SCK)** 作为唯一的屏幕与系统音
采集 framework；通过 `SCContentFilter` 区分全屏 / 窗口 / 区域三种模式，
通过 `SCStreamConfiguration.capturesAudio = true` 在同一个 `SCStream`
里同时拿到画面与系统音 sample buffer。

**Rationale**:

- macOS 15 (Sequoia) 上 SCK 已是 Apple 推荐的官方录屏路径，AVFoundation
  的旧 `AVCaptureScreenInput` 在 14+ 已被标记 deprecated。
- SCK 原生支持系统音录制，无需用户安装 BlackHole / Loopback 一类的
  第三方音频驱动 → 直接对齐宪法 II「普通用户简洁体验」原则。
- SCK 原生支持窗口级与区域级 filter，与 spec FR-005 / FR-007 / FR-008
  的"全屏 / 窗口 / 区域"三模一一对应。
- SCK 的 `SCContentSharingPicker`（macOS 15 引入）可以让窗口/区域选取
  直接走系统标准 UI，节省自研选择器的工作量并自动适配未来系统改动。

**Alternatives considered**:

- **AVFoundation `AVCaptureScreenInput`**: 已 deprecated；不支持系统
  音；不在 macOS 15 上长期可维护。**REJECT**.
- **CGDisplayStream / IOKit 低层 API**: 需要更多手写代码、性能与
  电源管理需要自己处理；和 SCK 比没有功能优势。**REJECT**.
- **第三方 SDK（如 OBS 框架）**: 引入大型依赖，违反"仅 Apple
  第一方"的依赖最小化原则；License 复杂。**REJECT**.

---

## R2 — Microphone (环境音) capture & mixing with system audio

**Decision**: 麦克风采集走 **AVFoundation `AVCaptureSession` +
`AVCaptureAudioDataOutput`**；系统音从 SCK 的 audio sample buffer 流
拿到；两路在 **`AVAssetWriter`** 写盘前用一个轻量 mixer
(`AudioMixingNode` 或自建 ring-buffer mixer) 同步混合到单条 AAC 音轨。

**Rationale**:

- SCK 不直接提供麦克风输入；`AVCaptureSession` 是 Apple 标准的麦克风
  采集路径，支持设备热插拔回调、采样率/通道数协商。
- 单一 AAC 音轨输出（而非两条独立 track）是 spec FR-011 的硬性要求
  ("混合到单一输出文件的音轨中")，且与 macOS 自带 QuickTime Player
  的默认播放行为一致。
- AVAssetWriter 是 macOS 上最成熟的封装路径，支持硬件加速编码（H.264 /
  HEVC via VideoToolbox）。

**Alternatives considered**:

- **CoreAudio AUGraph / AVAudioEngine 全程负责音频管线**: 灵活但复杂度
  高，容易引入采样率不匹配 / 时基漂移问题；v1 不需要的能力。**REJECT**.
- **两条独立音轨写入**: 与 FR-011 冲突；需要剪辑工具二次处理才能在
  普通播放器里听到环境音。**REJECT**.

---

## R3 — Encoding pipeline (mp4 / mov / m4a)

**Decision**: 使用 **AVAssetWriter + VideoToolbox 硬件加速**，默认
输出 mp4 (H.264 video + AAC audio)；可选输出 mov (H.264 或 HEVC + AAC)；
仅录音模式输出 m4a (AAC)。

| Mode             | Container | Video codec        | Audio codec |
|------------------|-----------|--------------------|-------------|
| 录屏（默认）     | mp4       | H.264 (Main, hw)   | AAC         |
| 录屏（可选）     | mov       | H.264 / HEVC (hw)  | AAC         |
| 仅录音           | m4a       | —                  | AAC         |

**Rationale**:

- mp4 + H.264 + AAC 是 macOS 自带 QuickTime / Finder 预览 / Mail 附件
  / iMessage 全链路开箱即用的最大公约数 → 满足 SC-004 "100% 可被
  QuickTime 完整播放"。
- VideoToolbox 硬件编码在 Apple Silicon / Intel 上均成熟，能轻松满足
  1080p 实时编码 + RSS ≤ 500 MB（SC-009）。
- 提供 mov + HEVC 作为可选项，给"想压更小文件"的用户出路，但默认
  保守以兼容性优先。
- m4a (AAC) 是仅录音模式的事实标准，体积比 wav 小一个数量级，且
  QuickTime / Music App 直接可放（FR-019）。

**Alternatives considered**:

- **ProRes 默认**: 体积是 H.264 的 5–10 倍，对面向普通用户的客户端
  来说"默认就 GB 级文件"会破坏宪法 II 的简洁体验。**REJECT** (作为
  未来可选项保留)。
- **WebM / VP9 / AV1**: macOS 自带播放器对 VP9 / AV1 的支持仍不一致；
  违反 SC-004。**REJECT**.
- **wav 用作仅录音模式**: 体积过大，普通用户场景下没必要。**REJECT**.

---

## R4 — Recording target picker (full-screen / window / region)

**Decision**: 优先使用 **`SCContentSharingPicker` (macOS 15+)** 走系统
标准选择器；同时维护一个轻量的"自家窗口列表 + 区域 overlay"作为
备用路径，覆盖 SCK picker 不展示某些边缘场景的情况（例如"已最小化
但用户希望录制"）。

**Rationale**:

- `SCContentSharingPicker` 是 Apple 在 macOS 15 引入的系统级选择器，
  外观与 macOS 14.4+ FaceTime / Zoom 等系统级共享 UI 完全一致 → 普通
  用户零学习成本（直接对齐宪法 II / IV）。
- macOS 15 同时引入了"应用级共享许可记忆"，可以避免每次录制都重新
  请求允许 → 显著降低 SC-001 的"完成首次录制 ≤ 90 s"摩擦。
- 自家选择器作为 fallback 仅承担 picker 不覆盖的边缘场景，工作量
  控制在 ~1 屏 SwiftUI list + 1 个 NSPanel overlay。

**Alternatives considered**:

- **完全自研窗口/区域选择器**: 工作量大，体验/可靠性都难超越系统
  picker，且无法享受 macOS 后续 picker 增强的红利。**REJECT** (仅作
  fallback)。
- **完全依赖 SCContentSharingPicker，不做 fallback**: 一旦 picker
  无法满足某场景（极少但存在），用户彻底没救济。**REJECT**.

---

## R5 — Global hotkey `⌃⇧K`

**Decision**: 使用 Carbon 的 **`RegisterEventHotKey`** API 注册全局
快捷键；在录制开始时注册，停止后立即注销；冲突时不阻塞录制本身。

**Rationale**:

- `RegisterEventHotKey` 是 macOS 上注册"系统级、跨 App 全局快捷键"
  的标准路径，**不需要辅助功能 (Accessibility) 权限** → 用户首次
  使用零授权弹窗摩擦。
- 仅在录制期间持有 hotkey，避免空闲时占用 → 也避免与其他常驻
  应用产生不必要的冲突。
- 失败可优雅降级（FR-029）：注册失败 → 系统通知 + 录制继续，菜单栏
  / 主窗口的停止路径仍 100% 可用。

**Alternatives considered**:

- **`NSEvent.addGlobalMonitorForEvents`**: 需要辅助功能权限，与宪法 II
  「最少摩擦」相悖。**REJECT**.
- **MASShortcut / KeyboardShortcuts (第三方 SPM)**: 成熟好用，但引入
  外部依赖；v1 hotkey 非常简单（固定键位），不值得引入第三方。
  **REJECT** (后续若做 hotkey 自定义可考虑)。
- **不注册全局 hotkey，仅靠菜单栏**: 已在 `/speckit-clarify` Q2 排除。

---

## R6 — App Sandbox entitlement set

**Decision**: 启用 App Sandbox，entitlement 集合保持最小：

```xml
<key>com.apple.security.app-sandbox</key>                       <true/>
<key>com.apple.security.device.audio-input</key>                <true/>
<key>com.apple.security.assets.movies.read-write</key>          <true/>
<key>com.apple.security.assets.music.read-write</key>           <true/>
<key>com.apple.security.files.user-selected.read-write</key>    <true/>
<key>com.apple.security.files.bookmarks.app-scope</key>         <true/>
```

屏幕录制权限走 macOS 的 TCC（Transparency, Consent, Control）系统，
不属于 entitlement，运行时自动触发系统授权对话框。

**Rationale**:

- 每一项 entitlement 都对应 spec 中的一项明确能力，无冗余：
  - `audio-input` → FR-009 / FR-010 麦克风录入
  - `assets.movies.read-write` → FR-021 默认 `~/Movies/Good Recording/`
  - `assets.music.read-write` → 仅录音模式可选放在 `~/Music/Good Recording/`
  - `user-selected.read-write` + `bookmarks.app-scope` → FR-021 用户
    自定义保存目录 + 跨重启持久化访问权限
- 没有 `com.apple.security.network.client/server`、
  `com.apple.security.cs.allow-unsigned-executable-memory` 等等任何
  网络 / 反沙箱 entitlement → 自动兑现宪法 I "本地优先" 的硬约束。

**Alternatives considered**:

- **不启用 Sandbox（仅靠 Hardened Runtime）**: 违反宪法 IV 与 macOS
  分发最佳实践。**REJECT**.
- **使用 `com.apple.security.temporary-exception.files.absolute-path`
  写 `~/Movies/`**: 多余，`assets.movies.read-write` 已覆盖。**REJECT**.

---

## R7 — Notarization & signing pipeline

**Decision**: 使用 `xcrun notarytool` (macOS 12+ 标准工具) 进行公证；
Developer ID Application 证书签名；公证完成后 `xcrun stapler staple`
将票据嵌入 .app 与 .dmg。

**Rationale**:

- `notarytool` 是 Apple 现役工具（替代旧 `altool`），稳定且支持
  CI 友好的 keychain profile 与 API key 两种鉴权方式。
- Stapling 让用户离线安装也能立刻通过 Gatekeeper 校验。
- 全流程脚本化在 `scripts/sign-and-notarize.sh`，CI 与本地开发者
  可复用。

**Alternatives considered**:

- **App Store 分发**: v1 不计划上架；分发渠道与 Sandbox 严格度可在
  后续版本切换。**DEFERRED**.
- **不公证（仅签名）**: macOS 10.15+ 强制公证，不公证用户首次启动
  会被 Gatekeeper 拦截。**REJECT**.

---

## R8 — Universal Binary build & CI matrix

**Decision**: Xcode build setting `ARCHS = arm64 x86_64`；CI 在 Apple
Silicon runner 上构建 fat 二进制（`lipo` 由 Xcode 自动处理），并在
**两个独立 CI job**（一个 native arm64 跑 host，一个 x86_64 通过
Rosetta 2 跑）分别执行测试集。

**Rationale**:

- 直接对齐宪法 IV 的 Universal Binary 要求与 plan.md "Constraints" 中
  "CI 必须同时构建并测试 arm64 与 x86_64"。
- 通过 Rosetta 2 跑 x86_64 测试是当前最经济的覆盖方式（Intel runner
  已稀缺）。
- 为未来"Intel 用户占比 < 5% 后移除 x86_64"留好出口（只需删一行
  build setting + 一个 CI job）。

**Alternatives considered**:

- **仅 arm64**: 违反宪法 IV"必须发布 Universal Binary"。**REJECT**.
- **每次 release 手工 lipo 合并 single-arch 产物**: 易错，CI 不
  reproducible。**REJECT**.

---

## R9 — Logging (本地结构化日志)

**Decision**: 双层日志：

- **OSLog (`os_log` / Swift `Logger`)** — 短消息、运行期诊断、
  Console.app 可视；
- **JSON Lines logger** — 结构化关键事件（录制开始/停止、权限请求、
  保存路径、异常）落到沙箱 `Library/Logs/GoodRecording/YYYY-MM-DD.log`，
  按天滚动、保留最近 30 天 / 100 MB（取较小者）。

应用菜单 "帮助 → 查看日志" 一键 `NSWorkspace.open(logsDirURL)`。
"导出日志" → `NSSavePanel` 把当前日志目录打包为 zip。
"清空日志" → 二次确认后 `FileManager.removeItem(at:)`。

**Rationale**:

- 直接对齐宪法 V "结构化、用户可见、可导出、可清空"。
- OSLog 满足开发者诊断需要；JSON Lines 满足"用户/支持人员能拿走"
  的可携带性需要。
- 30 天 / 100 MB 上限避免磁盘吃满（与 spec edge case "磁盘空间不足"
  联动）。

**Alternatives considered**:

- **仅 OSLog**: 用户难以直接导出，违反宪法 V。**REJECT**.
- **第三方日志 SDK (CocoaLumberjack)**: 不必要的依赖；OSLog +
  ~150 行自家 JSON Lines 完全够用。**REJECT**.

---

## R10 — Testing strategy (考虑到 SCK 的 TCC 约束)

**Decision**: 三层测试 + 一个 macOS VM 快照（"已预授权 Screen
Recording / Microphone / Notifications"）作为 integration / UI 测试
的运行环境。

| 层 | 框架 | 覆盖范围 | TCC 依赖 |
|---|---|---|---|
| Unit | Swift Testing | Core/* + Features/* 内部纯逻辑（编码配置生成、文件命名、热键管理 actor、混音 buffer） | 否 |
| Integration | XCTest + Fixture | Capture pipeline 端到端（短时录屏 + 写盘 + 验证文件可解码） | **是**（VM 快照） |
| UI | XCUITest + Accessibility Inspector script | 主流程烟雾、HIG / VoiceOver 抽样 | **是**（VM 快照） |

**Rationale**:

- ScreenCaptureKit 与 Microphone 在 CI 环境必须 TCC 授权才能跑通；
  GitHub-hosted runner 默认没有这些授权，因此采用 self-hosted VM
  快照（每次启动从已授权的 base snapshot 还原）。
- 单元测试覆盖率必须 ≥ 80%（覆盖到 Core/* 全部公共 API）。
- 每个 user story 的 acceptance scenario 至少对应 1 个 UI / Integration
  测试（兑现宪法 III 的"独立可测"硬约束）。

**Alternatives considered**:

- **完全靠手工测试**: 违反宪法 III NON-NEGOTIABLE 原则。**REJECT**.
- **GitHub-hosted runner 直接跑 SCK 测试**: TCC 在 headless CI 上拒绝
  授权，测试根本起不来。**REJECT**.

---

## Summary

| ID  | Decision area                           | Picked                                          | Status   |
|-----|-----------------------------------------|-------------------------------------------------|----------|
| R1  | Screen + system audio capture           | ScreenCaptureKit                                | ✅ Final |
| R2  | Mic capture + mixing                    | AVCaptureSession + AVAssetWriter mixer          | ✅ Final |
| R3  | Encoding & containers                   | AVAssetWriter + VideoToolbox; mp4/mov/m4a       | ✅ Final |
| R4  | Recording target picker                 | SCContentSharingPicker (+ self-built fallback)  | ✅ Final |
| R5  | Global hotkey                           | Carbon `RegisterEventHotKey`                    | ✅ Final |
| R6  | App Sandbox entitlements                | Minimal set (no network)                        | ✅ Final |
| R7  | Notarization                            | `notarytool` + `stapler`                        | ✅ Final |
| R8  | Universal Binary CI                     | `ARCHS = arm64 x86_64`; dual-arch CI matrix     | ✅ Final |
| R9  | Logging                                 | OSLog + JSON Lines (rotating, user-exportable)  | ✅ Final |
| R10 | Testing strategy                        | Swift Testing + XCTest + VM snapshot           | ✅ Final |

**No `NEEDS CLARIFICATION` markers remain. Ready for Phase 1.**
