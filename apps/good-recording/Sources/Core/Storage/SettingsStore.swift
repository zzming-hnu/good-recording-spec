// good-recording — Core/Storage/SettingsStore.swift (T018)
//
// UserDefaults-backed Settings persistence + security-scoped bookmark
// resolution for user-selected save dirs (FR-021).
// Source of truth: home-spec/specs/001-good-recording/contracts/output-files.md

import Foundation

/// 单例 — 整个 app 用同一个实例。线程安全靠 actor isolation（被
/// `@MainActor` 调用方拥有），跨进程一致性靠 UserDefaults 保证。
@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    @Published public private(set) var settings: Settings
    @Published public private(set) var lastUsedPreset: RecordingPreset

    // ── Persistence keys ────────────────────────────────────────────
    private enum Key {
        static let settings           = "good.recording.settings.v1"
        static let lastUsedPreset     = "good.recording.preset.lastUsed.v1"
        static let saveDirBookmark    = "good.recording.savedir.bookmark.v1"
    }

    private let defaults = UserDefaults.standard

    private init() {
        self.settings = SettingsStore.loadSettings(from: UserDefaults.standard)
        self.lastUsedPreset = SettingsStore.loadPreset(from: UserDefaults.standard)
    }

    // MARK: Settings persistence

    public func update(_ mutation: (inout Settings) -> Void) {
        var newValue = settings
        mutation(&newValue)
        settings = newValue
        persistSettings(newValue)
    }

    public func restoreFactoryDefaults() {
        let factory = Settings.factoryDefault()
        settings = factory
        persistSettings(factory)

        let preset = RecordingPreset.factoryDefault
        lastUsedPreset = preset
        persistPreset(preset)
    }

    // MARK: Preset persistence (隐式 _lastUsed)

    public func updateLastUsedPreset(_ mutation: (inout RecordingPreset) -> Void) {
        var p = lastUsedPreset
        mutation(&p)
        lastUsedPreset = p
        persistPreset(p)
    }

    // MARK: Custom save directory (security-scoped bookmark)

    /// 用户在 NSOpenPanel 选了一个新目录；调用者已经拿到 URL。
    public func setCustomSaveDirectory(_ url: URL, for mode: RecordingMode) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey(for: mode))

        update { s in
            switch mode {
            case .video:     s.defaultSaveDirectoryURL = url
            case .audioOnly: s.audioOnlySaveDirectoryURL = url
            }
        }
    }

    /// 启动时恢复用户选过的自定义目录；失败回落到默认 ~/Movies/Good Recording/。
    public func resolveCustomSaveDirectory(for mode: RecordingMode) -> URL {
        guard let bookmark = defaults.data(forKey: bookmarkKey(for: mode)) else {
            return settings.saveDirectory(for: mode)
        }
        var stale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        else {
            // bookmark 解析失败 → fall back + 一次性清理
            defaults.removeObject(forKey: bookmarkKey(for: mode))
            return settings.saveDirectory(for: mode)
        }
        if stale {
            // 路径变了 — 重写 bookmark；不阻塞调用者。
            if let fresh = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(fresh, forKey: bookmarkKey(for: mode))
            }
        }
        _ = url.startAccessingSecurityScopedResource()
        // 故意不在这里 stop —— 录制结束后 caller 调用一次 stop。
        return url
    }

    public func stopAccessingCustomSaveDirectory(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: Helpers

    private func bookmarkKey(for mode: RecordingMode) -> String {
        switch mode {
        case .video:     return Key.saveDirBookmark + ".video"
        case .audioOnly: return Key.saveDirBookmark + ".audioOnly"
        }
    }

    private func persistSettings(_ s: Settings) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: Key.settings)
        }
    }

    private func persistPreset(_ p: RecordingPreset) {
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: Key.lastUsedPreset)
        }
    }

    private static func loadSettings(from defaults: UserDefaults) -> Settings {
        if let data = defaults.data(forKey: Key.settings),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            return s
        }
        let factory = Settings.factoryDefault()
        if let data = try? JSONEncoder().encode(factory) {
            defaults.set(data, forKey: Key.settings)
        }
        return factory
    }

    private static func loadPreset(from defaults: UserDefaults) -> RecordingPreset {
        if let data = defaults.data(forKey: Key.lastUsedPreset),
           let p = try? JSONDecoder().decode(RecordingPreset.self, from: data) {
            return p
        }
        let factory = RecordingPreset.factoryDefault
        if let data = try? JSONEncoder().encode(factory) {
            defaults.set(data, forKey: Key.lastUsedPreset)
        }
        return factory
    }
}
