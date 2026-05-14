// good-recording — Features/US2-ScopeSelection/WindowPickerOverlay.swift (T058)
//
// Self-built fallback window picker — an NSPanel showing a list of
// visible windows with app icon + title + search field.
//
// Source of truth: contracts/ui-surfaces.md S5

import SwiftUI
import AppKit

struct WindowPickerOverlayView: View {

    @ObservedObject var vm: WindowPickerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search field (S5: filters incrementally)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索窗口…", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("WindowSearchField")
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            if vm.showsEmptyState {
                emptyState
            } else {
                windowList
            }
        }
        .frame(width: 360, height: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onAppear {
            Task { await vm.refreshWindows() }
        }
    }

    private var windowList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(vm.filteredWindows, id: \.windowID) { snap in
                    WindowRow(snap: snap) {
                        vm.selectWindow(snap)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // S5: empty state "没有可录制的窗口" + "重新扫描"
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("没有可录制的窗口")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("重新扫描") {
                Task { await vm.refreshWindows() }
            }
            .controlSize(.regular)
            Spacer()
        }
    }
}

// MARK: - Window row

private struct WindowRow: View {

    let snap: WindowSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                appIcon
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.windowTitle)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(snap.windowTitle), \(appName)")
    }

    private var appIcon: some View {
        Group {
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: snap.appBundleID
            ).first, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appName: String {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: snap.appBundleID
        ).first?.localizedName ?? snap.appBundleID
    }
}

// MARK: - NSPanel host

@MainActor
final class WindowPickerPanel {

    private var panel: NSPanel?
    private var hostView: NSHostingView<WindowPickerOverlayView>?

    func show(vm: WindowPickerViewModel) {
        let view = WindowPickerOverlayView(vm: vm)
        let hostView = NSHostingView(rootView: view)
        hostView.frame = NSRect(x: 0, y: 0, width: 360, height: 400)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "选择窗口"
        panel.contentView = hostView
        panel.center()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.hostView = hostView
    }

    func dismiss() {
        panel?.close()
        panel = nil
        hostView = nil
    }
}
