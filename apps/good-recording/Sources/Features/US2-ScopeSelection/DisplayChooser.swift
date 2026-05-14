// good-recording — Features/US2-ScopeSelection/DisplayChooser.swift (T056)
//
// Dropdown shown only when >= 2 displays are connected.
// Lets the user pick which display to record in full-screen mode.
//
// Source of truth: contracts/ui-surfaces.md S2 — "整个屏幕" segment

import SwiftUI
import CoreGraphics

struct DisplayChooserView: View {

    @Binding var selectedDisplayID: CGDirectDisplayID
    let displayCount: Int

    var body: some View {
        HStack {
            Label("选择显示器", systemImage: "display")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("显示器", selection: $selectedDisplayID) {
                ForEach(availableDisplays, id: \.self) { displayID in
                    Text(displayLabel(for: displayID))
                        .tag(displayID)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("DisplayChooser")
        }
    }

    private var availableDisplays: [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private func displayLabel(for id: CGDirectDisplayID) -> String {
        let isMain = id == CGMainDisplayID()
        let w = CGDisplayPixelsWide(id)
        let h = CGDisplayPixelsHigh(id)
        let suffix = isMain ? " (主显示器)" : ""
        return "\(w)×\(h)\(suffix)"
    }
}
