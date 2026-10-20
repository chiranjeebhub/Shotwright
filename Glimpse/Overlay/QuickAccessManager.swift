import AppKit
import SwiftUI

/// Stacks capture thumbnails in the bottom-left corner of the screen, newest at the bottom.
@MainActor
final class QuickAccessManager {
    static let shared = QuickAccessManager()

    static let cardSize = CGSize(width: 248, height: 156)
    private static let margin: CGFloat = 24
    private static let spacing: CGFloat = 12
    /// Room around the card for its shadow.
    private static let inset: CGFloat = 16

    private var panels: [QuickAccessPanel] = []

    func show(_ capture: Capture) {
        present(QuickAccessPanel(item: capture, content: QuickAccessCard(capture: capture), inset: Self.inset))
    }

    func show(_ recording: Recording) {
        present(QuickAccessPanel(item: recording, content: RecordingCard(recording: recording), inset: Self.inset))
    }

    private func present(_ panel: QuickAccessPanel) {
        panels.append(panel)
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    /// Removes the card for a capture or recording.
    func dismiss(_ item: AnyObject) {
        guard let index = panels.firstIndex(where: { $0.item === item }) else { return }
        let panel = panels.remove(at: index)
        panel.orderOut(nil)
        layout()
    }

    private func layout() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        var y = area.minY + Self.margin - Self.inset
        for panel in panels.reversed() {
            panel.setFrameOrigin(NSPoint(x: area.minX + Self.margin - Self.inset, y: y))
            y += Self.cardSize.height + Self.spacing
        }
    }
}

final class QuickAccessPanel: NSPanel {
    /// The capture or recording the card shows.
    let item: AnyObject

    @MainActor
    init<Content: View>(item: AnyObject, content: Content, inset: CGFloat) {
        self.item = item
        let size = CGSize(width: QuickAccessManager.cardSize.width + inset * 2, height: QuickAccessManager.cardSize.height + inset * 2)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: content.padding(inset))
    }

    override var canBecomeKey: Bool { false }
}
