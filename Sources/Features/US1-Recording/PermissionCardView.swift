// good-recording — Features/US1-Recording/PermissionCardView.swift (T042)
//
// "需要您的允许" card per contracts/ui-surfaces.md S7. Three-element copy
// (what / why / next-step button), with privacy reassurance line.

import SwiftUI

struct PermissionCardView: View {
    let missing: Permission
    let onOpenSettings: () -> Void
    let onDismiss:      () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                Text("需要您的允许才能\(missing.humanName)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "macOS 出于隐私保护，需要您在系统设置中手动授予 \(missing.humanName) 权限。")
                Text(verbatim: "我们不会将任何数据发送到设备之外。")
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("稍后再说") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("打开系统设置") { onOpenSettings() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("OpenSystemSettings")
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.tint.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 16, y: 4)
        .padding(40)
    }

    private var icon: String {
        switch missing {
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .microphone:      return "mic"
        case .notifications:   return "bell.badge"
        }
    }
}
