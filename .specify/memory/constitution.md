<!--
SYNC IMPACT REPORT
==================
Version change: TEMPLATE (uninitialized) → 1.0.0
Bump rationale: Initial ratification — first time placeholders are replaced
                with concrete principles, governance, and platform constraints.

Modified principles:
  - I. 本地优先与隐私保护 (Local-First & Privacy)              [NEW]
  - II. 普通用户为中心的简洁体验 (User-Centric Simplicity)      [NEW]
  - III. 独立可测与渐进交付 (Independent Testability & Delivery) [NEW]
  - IV. macOS 原生与平台一致性 (Native macOS Conformance)       [NEW]
  - V. 本地可观测与可恢复 (Local Observability & Recoverability) [NEW]

Added sections:
  - macOS Platform Constraints (deployment, sandbox, signing, performance)
  - Development Workflow (Spec→Plan→Tasks gates, review, release gates)
  - Governance (amendment, versioning, compliance review)

Removed sections: None (initial fill; no prior content to remove).

Templates requiring updates:
  - ✅ .specify/templates/plan-template.md  (Constitution Check section
        rewritten to enumerate the five principles as concrete gates)
  - ✅ .specify/templates/spec-template.md  (no changes — remains
        principle-agnostic; constraints land in plan + checklist)
  - ✅ .specify/templates/tasks-template.md (no changes — task taxonomy
        already supports independent-story / observability tasks)
  - ✅ .specify/templates/checklist-template.md (no changes — generic)
  - ✅ .cursor/rules/specify-rules.mdc      (no changes — generic guidance)

Follow-up TODOs:
  - TODO(PROJECT_DISPLAY_NAME): Confirm "Home Spec" is the intended product
    display name; update first heading and any future README accordingly.
  - TODO(MIN_MACOS_VERSION): Record the exact minimum macOS version once
    chosen in the first plan.md (currently expressed as a SHOULD policy).
-->

# Home Spec Constitution

## Core Principles

### I. 本地优先与隐私保护 (Local-First & Privacy) — NON-NEGOTIABLE

所有用户数据 MUST 存储在用户本地设备（macOS 文件系统、SQLite 或 Core Data
等容器中），未经用户在 UI 内显式授权，不得上传至任何远端服务、第三方分析
平台或云存储。所有计算过程 MUST 在本地完成；当某项功能不可避免需要联网
（例如外部 API 调用）时，必须：(a) 在使用前的 UI 中显式说明用途、传输内容、
接收方；(b) 提供"拒绝并继续使用"的降级路径；(c) 在本地日志中留下可审计
的记录。任何遥测（telemetry）、崩溃上报、A/B 实验在默认配置下 MUST 关闭。

**Rationale**: 客户端面向个人/家庭场景的私密信息，本地优先是默认信任模型，
也与 macOS App Sandbox、隐私清单（Privacy Manifest）等平台机制天然契合，
是产品差异化的核心承诺。

### II. 普通用户为中心的简洁体验 (User-Centric Simplicity)

功能与界面 MUST 面向无技术背景的普通用户设计：

- 主路径完成 MUST 不超过 3 步操作；首屏 MUST 一目了然，不需要阅读说明。
- 文案 MUST 使用日常用语；禁止向终端用户暴露技术词汇（例如 "JSON"、
  "YAML"、"路径"、"endpoint"、"hash"），如必须出现则需配合人类可读解释。
- 所有可逆操作 MUST 提供撤销（Undo）或最近 N 次回退；不可逆操作 MUST 在
  执行前以二次确认对话框清晰告知后果与影响范围。
- 错误信息 MUST 包含「发生了什么 / 可能原因 / 用户下一步可以做什么」三要素，
  禁止仅展示错误代码或调用栈。

**Rationale**: 目标用户群体决定产品边界。简洁直观不是审美选择，而是
普通用户能够独立完成核心任务的功能性前提。

### III. 独立可测与渐进交付 (Independent Testability & Incremental Delivery) — NON-NEGOTIABLE

每个功能（user story）MUST 同时满足以下条件才能合入主干：

- 拥有自动化的单元测试 + 至少一个端到端验收用例（acceptance test），
  并能在不依赖其他未发布功能的情况下完成验证。
- 可被独立打开/关闭（feature flag、模块化加载或独立菜单入口），以支持
  灰度发布与快速回滚；禁止跨 user story 的硬编码依赖。
- 通过最小可行版本（MVP）→ 内部灰度 → 全量 三阶段交付；禁止一次性
  大爆炸式发布。每个阶段 MUST 在 plan.md 中明确退出标准。

**Rationale**: 客户端发布周期长、回滚成本高（用户需要主动升级），独立可测
与渐进上线是控制质量风险与缩短反馈循环的唯一可扩展手段。

### IV. macOS 原生与平台一致性 (Native macOS & Platform Conformance)

应用 MUST 通过 macOS 平台的安全与体验基线：

- 通过 App Sandbox、Hardened Runtime、Notarization、Gatekeeper 校验；
  分发包（DMG/PKG/zip）首次启动 MUST 不出现任何安全警告。
- 界面 MUST 遵循 Apple Human Interface Guidelines：菜单栏、键盘快捷键、
  深色/浅色模式自适应、Retina 资源、辅助功能（VoiceOver、Dynamic Type）、
  系统标准对话框与窗口行为。
- 最低支持系统 SHOULD 不低于「当前正式版 − 2 个大版本」（例如当前为
  macOS 15，则支持 macOS 13+）；提升或降低下限的决定 MUST 在受影响的
  plan.md 中记录影响范围与迁移路径。
- MUST 发布 Universal Binary（Apple Silicon + Intel），直至明确以数据
  驱动证明 Intel 用户占比 < 5% 后方可移除。

**Rationale**: 部署目标决定技术约束。符合 Apple 生态规范不仅是合规要求，
更直接影响分发渠道（公证、企业分发、未来 App Store）与用户的安装信任。

### V. 本地可观测与可恢复 (Local Observability & Recoverability)

本地优先意味着没有云端兜底，因此用户必须有能力自查、自救、自迁移：

- 所有关键操作（数据写入、迁移、外部交互、权限请求）MUST 在本地生成
  结构化日志（如 JSON Lines）；日志 MUST 用户可见、可导出、可清空。
- 所有用户数据 MUST 提供明文导出能力（JSON / Markdown / CSV 任一），
  以保证可携带性，避免供应商锁定。
- 应用 MUST 在每次破坏性变更（schema 迁移、批量删除、覆盖性导入）前
  自动创建本地快照或备份；快照保留策略 MUST 在 spec.md 中明确（默认
  保留最近 5 次或 30 天，取较大者）。
- 崩溃 MUST 生成本地崩溃报告，路径在「关于」窗口可见，由用户自行决定
  是否分享给开发者。

**Rationale**: 没有云端的产品对"可恢复"的要求更高。可观测与可恢复是
本地优先承诺的另一面，缺一不可。

## macOS Platform Constraints

- **分发与签名**: 安装包 MUST 使用 Apple Developer ID 签名并通过公证
  （notarization）；自动更新（如使用 Sparkle）MUST 校验签名链。
- **沙箱与权限**: 申请的 entitlements MUST 遵循最小权限原则；
  网络、相机、麦克风、文件系统访问 MUST 在隐私清单（Privacy Manifest）
  中声明用途，并在首次触发时以系统标准提示请求。
- **数据存储位置**: 用户数据 MUST 存储在沙箱容器
  (`~/Library/Containers/<bundle-id>/`)、`Application Support/<bundle-id>/`
  或用户显式选择的目录；禁止写入系统目录或共享 `/tmp`。
- **性能基线（Apple Silicon）**: 冷启动 ≤ 2.0s；常驻内存 ≤ 200 MB（空闲态）；
  主交互响应 ≤ 100 ms p95；突破任一指标 MUST 在 plan.md 的 Complexity
  Tracking 中说明并提出补偿方案。
- **架构兼容**: 默认发布 Universal Binary；CI MUST 同时构建并测试
  arm64 与 x86_64 产物。
- **无障碍**: MUST 通过 macOS Accessibility Inspector 的零警告检查；
  全部交互控件 MUST 有 VoiceOver 标签与键盘可达路径。

## Development Workflow

- **流程**: 所有功能 MUST 遵循 Spec Kit 工作流：spec.md → plan.md → tasks.md
  → implement；每一步 MUST 在前一步通过评审后开始。
- **宪法门禁 (Constitution Check)**: plan.md 在 Phase 0 与 Phase 1 之后
  MUST 显式校验本宪法五项原则；任何违背 MUST 在 "Complexity Tracking"
  中记录正当理由及"被拒绝的更简方案"。
- **测试策略**: 每个 user story 在合并前 MUST 包含独立可执行的端到端
  验收用例；NON-NEGOTIABLE 原则相关功能（隐私边界、独立性）MUST 采用
  TDD（红 → 绿 → 重构），测试 MUST 先于实现提交。
- **代码评审**: 所有 PR MUST 至少 1 名同等级以上工程师评审；触及隐私边界
  （网络请求、数据存储位置、权限申请、签名/公证配置）的 PR MUST 由项目
  负责人额外签字。
- **发布门禁**: 每次发布前 MUST 通过 (1) 自动化测试全部通过；
  (2) 公证回执成功；(3) Accessibility & 沙箱清单核对；
  (4) 在最低支持的 macOS 版本上的烟雾测试；(5) 灰度阶段无 P0/P1 缺陷
  滞留 ≥ 7 天。

## Governance

本宪法是项目的最高规范。所有 spec、plan、tasks、code review 标准 MUST 与之
保持一致；冲突时以本宪法为准。

- **修订流程**: 任何修订 MUST 通过 PR 提交，并在 PR 描述中列出
  (1) 改动内容；(2) 受影响的模板/文档清单；(3) 已合入功能的迁移计划；
  (4) 版本号变更原因，且由至少 2 名核心维护者批准后方可合入。
- **版本策略 (SemVer)**:
  - **MAJOR**: 移除原则、不向下兼容地重新定义原则、变更治理流程。
  - **MINOR**: 新增原则或章节、显著扩展指导内容。
  - **PATCH**: 措辞修正、错别字、非语义性优化。
- **合规审查**: 每个发布周期 MUST 进行一次宪法符合性自检，结果记入该周期
  的 retrospective；若连续两次发现同类违背 MUST 触发原则修订或工具化兜底
  （如 lint 规则、CI 检查、模板更新）。
- **运行时指导**: 实际开发与命令指导请参考 `.cursor/rules/specify-rules.mdc`
  以及 `.specify/templates/` 下的各模板。

**Version**: 1.0.0 | **Ratified**: 2026-05-07 | **Last Amended**: 2026-05-07
