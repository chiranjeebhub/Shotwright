import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: [EditorWindowController] = []

    static func open(_ capture: Capture) {
        if let existing = openControllers.first(where: { $0.model.capture === capture }) {
            existing.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = EditorWindowController(capture: capture)
        openControllers.append(controller)
        // Show in the Dock and ⌘-Tab while an editor is open.
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let model: EditorModel

    private init(capture: Capture) {
        model = EditorModel(capture: capture)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Glimpse — Annotate"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar tall enough to hold our tool row.
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.contentView = NSHostingView(rootView: EditorView(model: model) { [weak window] in window?.close() })
        window.delegate = self
        let screen = NSScreen.underMouse.visibleFrame
        window.setContentSize(NSSize(width: min(1200, screen.width - 80), height: min(760, screen.height - 80)))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
        if Self.openControllers.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
