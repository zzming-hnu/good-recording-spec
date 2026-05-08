// good-recording — Core/Hotkey/GlobalHotkey.swift (T021)
//
// Carbon RegisterEventHotKey wrapper for the v1 fixed global hotkey ⌃⇧K.
// No Accessibility permission required (per research.md R5).
// Source of truth: home-spec/specs/001-good-recording/contracts/ui-surfaces.md
// (Global hotkey contract section) + spec.md FR-027 / FR-028 / FR-029.
//
// Concurrency note: Carbon types (EventHotKeyRef, EventHandlerRef) are
// `OpaquePointer` and not Sendable. We use a plain NSLock — not
// OSAllocatedUnfairLock — so the lock body is *not* a @Sendable closure
// and can capture these pointer types safely.

import Foundation
import Carbon.HIToolbox

public enum HotkeyRegistration: Sendable, Equatable {
    case registered
    case conflict
    case failed(reasonCode: Int32)
}

public final class GlobalHotkey: @unchecked Sendable {
    public static let shared = GlobalHotkey()

    private static let hotkeyID = EventHotKeyID(
        signature: OSType(0x4752_4F47),   // 'GROG' — good-recording
        id: 1
    )

    // ── Internal state (NSLock-protected) ────────────────────────────
    private let lock = NSLock()
    private var hotkeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onTrigger: (@Sendable () -> Void)?

    private init() {}

    // MARK: Public API

    @discardableResult
    public func register(onTrigger: @escaping @Sendable () -> Void) -> HotkeyRegistration {
        lock.lock()
        unregisterLocked()
        self.onTrigger = onTrigger
        lock.unlock()

        installEventHandler()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(controlKey | shiftKey),
            Self.hotkeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            lock.lock()
            self.hotkeyRef = ref
            lock.unlock()
            return .registered
        } else if status == OSStatus(eventHotKeyExistsErr) {
            return .conflict
        } else {
            return .failed(reasonCode: status)
        }
    }

    public func unregister() {
        lock.lock()
        unregisterLocked()
        lock.unlock()
    }

    /// Pulled out as nonisolated entry point for the C callback.
    fileprivate func fire() {
        lock.lock()
        let cb = onTrigger
        lock.unlock()
        cb?()
    }

    // MARK: Private

    private func unregisterLocked() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        onTrigger = nil
    }

    private func installEventHandler() {
        lock.lock()
        let already = (handler != nil)
        lock.unlock()
        if already { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var localHandler: EventHandlerRef?

        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotkeyCallback,
            1,
            &spec,
            selfPtr,
            &localHandler
        )

        if let h = localHandler {
            lock.lock()
            self.handler = h
            lock.unlock()
        }
    }
}

// Top-level C callback — file-private, captures nothing.
private func globalHotkeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ ctx: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let ctx else { return noErr }

    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    guard status == noErr, hkID.id == 1 else { return status }

    let me = Unmanaged<GlobalHotkey>.fromOpaque(ctx).takeUnretainedValue()
    me.fire()
    return noErr
}
