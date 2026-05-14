# good-recording

> 一个用 [Spec Kit](https://github.com/github/spec-kit) 驱动开发的本地优先 macOS 屏幕 + 音频录制工具。
>
> **本仓库 = 完整规范 (specs/) + 真实可运行的实现 (apps/good-recording/)。**

[![Status](https://img.shields.io/badge/v0.1-MVP-brightgreen)](#当前状态)
[![Tests](https://img.shields.io/badge/tests-36%2F36-brightgreen)]()
[![Tasks](https://img.shields.io/badge/tasks-63%2F118-blue)](specs/001-good-recording/tasks.md)
[![Constitution](https://img.shields.io/badge/constitution-v1.0.0-purple)](.specify/memory/constitution.md)
[![macOS](https://img.shields.io/badge/macOS-15%2B-lightgrey)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)]()

---

## 这是什么

**good-recording** 是一个面向普通用户的 macOS 录屏工具。一键录屏、一键停止、文件自动落到 `~/Movies/Good Recording/`，**所有数据本地存储，绝不联网**。

它的特别之处不在于产品本身（macOS 上录屏工具有几十个），而在于它的**整个开发过程** —— 从写第一行需求到产出可运行的 v0.1 MVP，全程严格按照 [GitHub Spec Kit](https://github.com/github/spec-kit) 的 **Spec-Driven Development** 流程：

```text
constitution → specify → clarify → plan → tasks → implement
   宪法           规范      澄清     计划    任务      实现
```

每一步的产出都在仓库里可追溯，每一行 Swift 代码都能反向追溯到一条 Functional Requirement。

---

## 当前状态

| 阶段 | 状态 | 备注 |
|---|---|---|
| 宪法 v1.0.0 (5 项原则) | ✅ | [.specify/memory/constitution.md](.specify/memory/constitution.md) |
| 功能规范 (5 个 user story / 29 个 FR / 10 条 SC) | ✅ | [specs/001-good-recording/spec.md](specs/001-good-recording/spec.md) |
| 实现计划 + 4 份 contracts + 数据模型 | ✅ | [specs/001-good-recording/plan.md](specs/001-good-recording/plan.md) |
| 任务清单 (118 任务) | ✅ | [specs/001-good-recording/tasks.md](specs/001-good-recording/tasks.md) |
| **Phase 1** Setup (T001–T012) | ✅ | 12/12 |
| **Phase 2** Foundational (T013–T029) | ✅ | 17/17 — 7 个 Core 模块 + 采集/编码管道 |
| **Phase 3** US1 一键录屏 MVP (T030–T047) | ✅ | 18/18 — **可真实运行 + 录到 mp4** |
| **Phase 4** US2 范围选择 (T048–T063) | ✅ | 16/16 — 全屏 / 窗口 / 自定义区域 + 多显示器 |
| **Phase 5** US3 音频源 UI (T064–T079) | ⏳ | 待实施 |
| **Phase 6** US4 质量与格式设置 (T080–T093) | ⏳ | 待实施 |
| **Phase 7** US5 仅音频录制 (T094–T103) | ⏳ | 待实施 |
| **Phase 8** Polish (T104–T118) | ⏳ | 待实施 |
| 单元测试 | ✅ | 36/36 PASS |
| Universal Binary 构建 + Developer ID 签名 + 公证脚本 | ✅ | 详见 [`apps/good-recording/scripts/`](apps/good-recording/scripts) |

**v0.1 MVP 已可真实运行**：单一录制按钮、`⌃⇧K` 全局停止、菜单栏状态项、系统通知、本地 JSON Lines 日志、沙箱化、自签证书工作流。

### 已知 v0.1 局限

- **mic + system 同时录入混音**：写了 `AVAudioEngine` 真混音路径但 buffer 流没调通，目前默认配置只录系统音；改 mic + system 同时开会回退到 v0.1 quick-fix 路径（system 优先，mic 被丢）。详见 [`apps/good-recording/Sources/Core/Encoding/AudioMixer.swift`](apps/good-recording/Sources/Core/Encoding/AudioMixer.swift) 的 KNOWN ISSUE 注释。**v0.2 优先修复**。

---

## 5 项宪法原则（NON-NEGOTIABLE 标 ⚠️）

| | 原则 | 含义 |
|---|---|---|
| I ⚠️ | **本地优先与隐私保护** | 全部数据本地存储；零网络出站；遥测默认关闭；权限申请均显式 |
| II | **普通用户为中心的简洁体验** | 主路径 ≤ 3 步；日常用语；可撤销 / 二次确认 |
| III ⚠️ | **独立可测与渐进交付** | 每个功能独立测试 + 独立 feature flag；MVP → 灰度 → 全量 |
| IV | **macOS 原生与平台一致性** | App Sandbox + Hardened Runtime + Notarization；遵循 HIG；Universal Binary |
| V | **本地可观测与可恢复** | 结构化本地日志（用户可导出）；明文数据导出；本地崩溃报告 |

完整版：[.specify/memory/constitution.md](.specify/memory/constitution.md)

---

## 仓库结构

```text
home-spec/                                        # 本仓库（monorepo）
├── .cursor/rules/                                # Cursor agent 自动加载的 always-applied 规则
├── .specify/                                     # Spec Kit 工具与扩展
│   ├── memory/constitution.md                    # 宪法
│   ├── templates/                                # spec / plan / tasks 模板
│   ├── extensions/git/                           # 自动化 hooks
│   └── workflows/                                # 工作流定义
├── specs/001-good-recording/                     # 本特性的全部规范
│   ├── spec.md                                   # 功能规范（5 user stories）
│   ├── plan.md                                   # 实现计划（含 6/6 Constitution Check）
│   ├── research.md                               # 10 项技术决策
│   ├── data-model.md                             # 实体 + 状态机
│   ├── contracts/                                # 4 份接口契约
│   │   ├── ui-surfaces.md                        # 10 个 UI 界面
│   │   ├── output-files.md                       # 文件命名 / 编码参数 / 落地契约
│   │   ├── permissions.md                        # TCC + entitlements 矩阵
│   │   └── logs.md                               # 日志 schema + 事件目录
│   ├── tasks.md                                  # 118 任务（带 [P] 并行标记 + [US{N}] 故事归属）
│   ├── quickstart.md                             # 开发构建/运行/测试指南
│   ├── troubleshooting.md                        # 11 个 macOS 26 dev 环境踩坑实录 ⭐
│   └── checklists/requirements.md                # 规范质量检查表
└── apps/
    └── good-recording/                           # macOS 应用实现
        ├── project.yml                           # XcodeGen 工程配置
        ├── README.md                             # 实现侧 README
        ├── Sources/
        │   ├── App/                              # @main / AppDelegate / FeatureFlags / MainWindow
        │   ├── Features/
        │   │   ├── US1-Recording/                # ✅ 一键录屏 (Phase 3)
        │   │   ├── US2-ScopeSelection/           # ✅ 范围选择 (Phase 4)
        │   │   ├── US3-AudioSources/             # ⏳ 待 Phase 5
        │   │   ├── US4-QualitySettings/          # ⏳ 待 Phase 6
        │   │   └── US5-AudioOnlyMode/            # ⏳ 待 Phase 7
        │   └── Core/                             # ✅ 7 个共享服务模块 (Phase 2)
        │       ├── Capture/                      # ScreenCaptureKit + 麦克风采集
        │       ├── Encoding/                     # AVAssetWriter + 音频混音
        │       ├── Storage/                      # 文件命名 / 设置持久化 / 数据模型
        │       ├── Permissions/                  # TCC 权限助手
        │       ├── Hotkey/                       # Carbon 全局快捷键 ⌃⇧K
        │       ├── Notifications/                # 系统通知 + 应用内 banner
        │       └── Logging/                      # JSON Lines 本地日志 + OSLog
        ├── Resources/                            # Info.plist / entitlements / Localizable
        ├── Tests/                                # 36/36 通过的单元测试
        └── scripts/
            ├── setup-xcode.sh                    # Xcode 一键收尾配置
            ├── make-local-cert.sh                # 本地自签代码签名证书
            ├── build-universal.sh                # Universal Binary 构建
            ├── sign-and-notarize.sh              # Developer ID 签名 + 公证
            ├── rebuild-and-reauth.sh             # 重建 + 重置 TCC 授权（dev 必备）
            └── ci/                               # 5 个 CI lint 脚本
```

---

## 快速开始

### 系统要求

| 工具 | 版本 | 说明 |
|---|---|---|
| macOS | 15.0+ (Sequoia) | 最低部署目标 |
| Xcode | 16.0+ | **完整版**，不能只装 Command Line Tools |
| Homebrew | latest | 装 XcodeGen 用 |
| XcodeGen | latest | `brew install xcodegen` |

### 5 步开跑

```bash
# 1. 克隆仓库
git clone <this-repo-url>
cd home-spec

# 2. 进入实现目录
cd apps/good-recording

# 3. 一键完成 Xcode 配置（首次跑会请求 sudo 切 xcode-select + 接受 license）
./scripts/setup-xcode.sh

# 4. 创建本地代码签名证书（绕开 macOS 26 对 ad-hoc 签名应用的录屏限制；
#    需要输入你的 macOS 登录密码 + sudo 密码）
./scripts/make-local-cert.sh

# 5. 重建 + 启动应用
./scripts/rebuild-and-reauth.sh
```

第 5 步执行完，应用窗口会弹出。点击 **开始录制**，跟随 macOS 的原生权限对话框授权一次后即可使用。

### 修改代码后如何快速验证

```bash
cd apps/good-recording && ./scripts/rebuild-and-reauth.sh --fast
```

`--fast` 跳过 DerivedData 清理，做增量重建。

### 出 Universal Binary 给朋友试

```bash
cd apps/good-recording
./scripts/build-universal.sh
# 产物：build/Release/GoodRecording.app
```

> 想公证分发：`./scripts/sign-and-notarize.sh build/Release/GoodRecording.app`，需要 Apple Developer Program ($99/年) + 在 Keychain 里配好 notarytool profile。

---

## 想了解开发流程

如果你对这个项目"如何用 Spec Kit 从零造一个 macOS 应用"感兴趣：

1. **从宪法开始读**: [.specify/memory/constitution.md](.specify/memory/constitution.md)（5 分钟，5 项原则）
2. **再读功能规范**: [specs/001-good-recording/spec.md](specs/001-good-recording/spec.md)（10 分钟，看 5 个 user story 怎么从 1 句话需求长出来）
3. **看 Clarifications 章节**: 用户和 AI 之间通过 5 个高价值问题锁定关键决策（最低 macOS 版本 / 全局快捷键 / 录制历史 / 崩溃恢复）
4. **看 plan.md + research.md**: 每条技术决策都带 rationale + alternatives
5. **看 tasks.md**: 118 任务按用户故事 + 优先级排好，可并行任务带 `[P]` 标记
6. **看 troubleshooting.md** ⭐: 11 个 macOS 26 dev 环境真实踩坑（TCC 静默拒绝、cdhash 漂移、Hardened Runtime 与 self-signed 不兼容、cfprefsd 缓存、AVAudioEngine 路径 buffer 丢失……）

**troubleshooting.md 是这个仓库最有商业价值的产物之一** —— 任何想在 macOS 26 上做 sandbox app + ScreenCaptureKit 的开发者都能直接复用。

---

## 路线图

按宪法 III"独立可测与渐进交付"原则，每个 Phase 独立 deliverable：

- **v0.2** （计划中）
  - 修复 `AudioMixer` 真混音路径（mic + system → 单条 AAC 音轨，对齐 spec FR-011）
  - **Phase 5 US3** 音频源 UI（让用户在主窗口独立勾选 mic / 系统音）
- **v0.3**
  - **Phase 6 US4** 质量与格式设置面板（720p / 1080p / 1440p / 原生；mp4 / mov；可自定义保存目录）
- **v0.4**
  - **Phase 7 US5** 仅音频录制模式（输出 m4a）
- **v1.0**
  - **Phase 8** Polish — 关于窗口 / 数据与日志面板 / 无障碍 / 性能基准 / CI 完善 / 真实分发版

---

## 贡献

欢迎 issue / PR。提交前请：

1. 通读 [.specify/memory/constitution.md](.specify/memory/constitution.md)，确保你的改动不触碰 NON-NEGOTIABLE 原则（I 本地优先、III 独立可测）
2. 如果是新功能 → 走 `/speckit-specify` 流程添加新 user story
3. 如果是 bug fix → 直接 PR，commit message 引用受影响的 FR / SC 编号
4. 如果是 dev 环境踩坑 → 在 [troubleshooting.md](specs/001-good-recording/troubleshooting.md) 加一个 Issue 段落
5. 跑完 `xcodebuild test -only-testing:UnitTests`（应该 36/36 PASS）

---

## 致谢与灵感

- [GitHub Spec Kit](https://github.com/github/spec-kit) —— 这套 Spec-Driven Development 流程的来源。本项目的 `.specify/` 目录、宪法/规范/计划/任务模板都来自 Spec Kit。
- Apple 的 `ScreenCaptureKit` 与 `AVFoundation` —— v0.1 全部录制能力的底座。
- macOS 26 那 11 个踩坑（已经全部记录在 troubleshooting.md）—— 每个都让这个项目更健壮一点。

---

## 许可

TBD（暂未确定，发布前会补上 MIT 或 Apache 2.0）。

---

> **如果你只看一份文档**，看 [`specs/001-good-recording/troubleshooting.md`](specs/001-good-recording/troubleshooting.md) —— 这是把"在 macOS 26 上做沙箱屏幕录制"这件事的所有暗坑摊在阳光下的一份指南。
