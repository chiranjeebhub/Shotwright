import AppKit
import SwiftUI

/// Keeps a capture floating above other windows, like a sticky reference image.
/// Drag to move, scroll or pinch to resize, double-click or Esc to close.
final class PinnedImageWindow: NSPanel {
    @MainActor private static var open: Set<PinnedImageWindow> = []

    @MainActor
    static func pin(_ capture: Capture) {
        let window = PinnedImageWindow(capture: capture)
        open.insert(window)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private init(capture: Capture) {
        let size = capture.pointSize
        let screen = NSScreen.underMouse.visibleFrame
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        aspectRatio = size
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView:
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture(count: 2) { [weak self] in self?.unpin() }
        )
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { unpin() }

    override func scrollWheel(with event: NSEvent) {
        let factor = 1 + event.scrollingDeltaY / 200
        var frame = self.frame
        let newWidth = max(80, frame.width * factor)
        let newHeight = newWidth * frame.height / frame.width
        frame.origin.x -= (newWidth - frame.width) / 2
        frame.origin.y -= (newHeight - frame.height) / 2
        frame.size = NSSize(width: newWidth, height: newHeight)
        setFrame(frame, display: true)
    }

    @MainActor
    private func unpin() {
        orderOut(nil)
        Self.open.remove(self)
    }
}
