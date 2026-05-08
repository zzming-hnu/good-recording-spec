// good-recording — Features/US1-Recording/PermissionCardView.swift (T042)
//
// "需要您的允许" card per contracts/ui-surfaces.md S7. Three-element copy
// (what / why / next-step button), with privacy reassurance line.

import SwiftUI

struct PermissionCardView: View {
    let missing: Permission
    let onOpenSettings: () -> Void
    let onDismiss:      () -> Void
    var onRetry: (() -> Void)? = nil

    @State private var showAdvanced = false

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

            // 「我已经给过权限了」展开区
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "如果你之前已经在系统设置里给过权限：")
                        .font(.subheadline.weight(.medium))
                    Text(verbatim: "1. 完全退出 good-recording (⌘Q)")
                    Text(verbatim: "2. 在「系统设置 → 隐私与安全性 → 屏幕录制」里把 good-recording 关掉再打开")
                    Text(verbatim: "3. 重新打开 good-recording 试一次")
                    Text(verbatim: "（开发版应用每次重新编译都会被 macOS 视作新应用，需要重新授权一次。正式分发版无此问题。）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                Text(verbatim: "我已经给过权限了？")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }

            HStack {
                Button("稍后再说") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                if let onRetry {
                    Button("重新检测") { onRetry() }
                }
                Spacer()
                Button("打开系统设置") { onOpenSettings() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("OpenSystemSettings")
            }
        }
        .padding(20)
        .frame(maxWidth: 480)
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
