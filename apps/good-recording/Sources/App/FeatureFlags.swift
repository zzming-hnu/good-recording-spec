// good-recording — Compile-time + runtime feature flags.
//
// Per Constitution III "独立可测与渐进交付", every user story ships behind
// a flag so MVP slices and progressive rollouts don't require code changes.
//
// Setting any flag to `false` removes the corresponding UI surface entirely
// (Features modules check this in their root view).
//
// Source of truth: home-spec/specs/001-good-recording/quickstart.md §2

import Foundation

public enum FeatureFlags {
    /// US1 — One-click record/stop/save. P1 / MVP. MUST stay `true` in
    /// shipped builds; the rest can be toggled off to ship a smaller v0.x.
    public static let US1_RECORDING = true

    /// US2 — Range selection (full-screen / window / region). P2.
    public static let US2_SCOPE_SELECTION = true

    /// US3 — Audio source toggles (环境音 / 系统音). P2.
    public static let US3_AUDIO_SOURCES = true

    /// US4 — Quality & format settings (resolution / container / codec). P3.
    public static let US4_QUALITY_SETTINGS = true

    /// US5 — Audio-only recording mode. P3.
    public static let US5_AUDIO_ONLY_MODE = true
}
