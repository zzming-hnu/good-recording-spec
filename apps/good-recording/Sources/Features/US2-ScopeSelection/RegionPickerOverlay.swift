// good-recording — Features/US2-ScopeSelection/RegionPickerOverlay.swift (T059)
//
// Full-screen transparent NSPanel overlay. User drags to draw a rectangle
// with resize handles + live size readout. Esc cancels; release confirms.
//
// Source of truth: contracts/ui-surfaces.md S6

import AppKit
import SwiftUI

@MainActor
final class RegionPickerOverlay: NSObject {

    private var panels: [NSPanel] = []
    private var overlayViews: [RegionDrawingView] = []

    var onRegionSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    /// Initial rect to display (from last session).
    var initialRect: CGRect?

    /// Show a transparent overlay on each active display.
    func show() {
        dismiss()

        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.hasShadow = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.3)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovable = false
            panel.acceptsMouseMovedEvents = true

            let overlay = RegionDrawingView(frame: screen.frame)
            overlay.initialRect = initialRect
            overlay.onComplete = { [weak self] rect in
                self?.handleSelection(rect, on: screen)
            }
            overlay.onCancel = { [weak self] in
                self?.dismiss()
                self?.onCancel?()
            }
            panel.contentView = overlay

            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
            overlayViews.append(overlay)
        }
    }

    func dismiss() {
        for panel in panels {
            panel.close()
        }
        panels.removeAll()
        overlayViews.removeAll()
    }

    private func handleSelection(_ rect: CGRect, on screen: NSScreen) {
        dismiss()
        // The drawing view uses AppKit coordinates (origin at bottom-left
        // of the panel, which spans the screen). Convert to CoreGraphics
        // global coordinates (origin at top-left of the main display)
        // because SCK's sourceRect uses CG coordinates.
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let globalRect = CGRect(
            x: screen.frame.origin.x + rect.origin.x,
            y: mainHeight - (screen.frame.origin.y + rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
        onRegionSelected?(globalRect)
    }
}

// MARK: - Drawing view (NSView-based for precise mouse tracking)

private class RegionDrawingView: NSView {

    var initialRect: CGRect?
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragOrigin: CGPoint?
    private var currentRect: CGRect?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if let initial = initialRect {
            // Show previous region as a dashed guide
            currentRect = convert(initial, from: nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Semi-transparent overlay
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.fill(bounds)

        guard let rect = currentRect else {
            // Draw crosshair cursor hint
            drawHint(ctx)
            return
        }

        // Cut out the selected region (make it clear)
        ctx.setBlendMode(.clear)
        ctx.fill(rect)
        ctx.setBlendMode(.normal)

        // Draw border around selected region
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(rect)

        // Draw corner handles
        drawHandles(ctx, in: rect)

        // Draw size label
        drawSizeLabel(ctx, for: rect)
    }

    private func drawHint(_ ctx: CGContext) {
        let text = "拖动选择录制区域，按 Esc 取消" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let point = CGPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
    }

    private func drawHandles(_ ctx: CGContext, in rect: CGRect) {
        let handleSize: CGFloat = 8
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            ctx.fillEllipse(in: handleRect)
        }
    }

    private func drawSizeLabel(_ ctx: CGContext, for rect: CGRect) {
        let w = Int(rect.width)
        let h = Int(rect.height)
        let label = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
        ]
        let size = label.size(withAttributes: attrs)
        let labelOrigin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.maxY + 8
        )
        label.draw(at: labelOrigin, withAttributes: attrs)
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let origin = dragOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(current.x - origin.x),
            height: abs(current.y - origin.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        guard let rect = currentRect, rect.width > 10, rect.height > 10 else {
            return
        }
        // S6: auto-confirm on release
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else if event.keyCode == 36 { // Enter — confirm current rect
            if let rect = currentRect, rect.width > 10, rect.height > 10 {
                onComplete?(rect)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
