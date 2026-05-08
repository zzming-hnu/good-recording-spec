// good-recording — Features/US1-Recording/SavedBannerView.swift (T040 + T041)
//
// In-window "已保存" banner with "在 Finder 中显示" action. Auto-fades after
// 5s (timing handled by RecordingViewModel).

import SwiftUI

struct SavedBannerView: View {
    let fileURL: URL
    let onShowInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "已保存")
                    .font(.headline)
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("在 Finder 中显示") { onShowInFinder() }   // T041
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.green.opacity(0.4), lineWidth: 1)
        )
        .shadow(radius: 8, y: 2)
    }
}
