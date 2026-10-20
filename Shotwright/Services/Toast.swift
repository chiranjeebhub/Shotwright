import AppKit
import SwiftUI

/// A small HUD message near the bottom of the screen, e.g. "Text copied to clipboard".
@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ message: String) {
        panel?.orderOut(nil)

        let host = NSHostingView(rootView:
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.08, opacity: 0.85)))
        )
        host.frame.size = host.fittingSize

        let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let screen = NSScreen.underMouse.visibleFrame
        panel.setFrameOrigin(NSPoint(x: screen.midX - host.frame.width / 2, y: screen.minY + 80))
        panel.orderFrontRegardless()
        self.panel = panel

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard Toast.panel === panel else { return }
            panel.orderOut(nil)
            Toast.panel = nil
        }
    }
}
