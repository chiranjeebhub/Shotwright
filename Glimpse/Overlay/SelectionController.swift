import AppKit
import ScreenCaptureKit

enum SelectionResult {
    /// `rect` is in the screen's local AppKit coordinates; `frozen` is the full-screen
    /// image taken when the overlay opened, which the selection is cropped from.
    case area(rect: CGRect, screen: NSScreen, frozen: Capture)
    case window(SCWindow)
}

/// Runs the full-screen selection overlay across every display.
@MainActor
final class SelectionController {
    enum Mode { case area, window }

    private(set) var mode: Mode
    private let windows: [SCWindow]
    private let frozen: [CGDirectDisplayID: Capture]
    private let completion: (SelectionResult?) -> Void

    private var overlays: [SelectionWindow] = []
    private var monitors: [Any] = []
    private(set) var hoveredWindow: SCWindow?
    private(set) var mouseLocation: NSPoint = NSEvent.mouseLocation

    init(mode: Mode, windows: [SCWindow], frozen: [CGDirectDisplayID: Capture], completion: @escaping (SelectionResult?) -> Void) {
        self.mode = mode
        self.windows = windows
        self.frozen = frozen
        self.completion = completion
    }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen, controller: self, frozen: frozen[screen.displayID])
            window.orderFrontRegardless()
            overlays.append(window)
        }
        (overlays.first { $0.screen == NSScreen.underMouse } ?? overlays.first)?.makeKey()

        addMonitor(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.mouseMoved()
            return event
        })
        addMonitor(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Esc
                self.finish(nil)
                return nil
            case 49: // Space
                self.toggleMode()
                return nil
            default:
                return event
            }
        })
        addMonitor(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.redrawAll()
            return event
        })
        mouseMoved()
    }

    private func addMonitor(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    func frozenImage(for screen: NSScreen) -> Capture? { frozen[screen.displayID] }

    /// The hovered window's frame in `view`'s coordinates, if it overlaps that view's screen.
    func hoveredWindowRect(in screen: NSScreen) -> NSRect? {
        guard mode == .window, let hoveredWindow else { return nil }
        let global = appKitRect(fromCG: hoveredWindow.frame)
        guard global.intersects(screen.frame) else { return nil }
        return global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    func finishArea(_ rect: NSRect, on screen: NSScreen) {
        guard let image = frozen[screen.displayID] else { finish(nil); return }
        finish(.area(rect: rect, screen: screen, frozen: image))
    }

    func finishWindow() {
        guard let hoveredWindow else { return }
        finish(.window(hoveredWindow))
    }

    private func toggleMode() {
        mode = (mode == .area) ? .window : .area
        overlays.forEach { $0.selectionView.cancelDrag() }
        mouseMoved()
    }

    private func mouseMoved() {
        mouseLocation = NSEvent.mouseLocation
        if mode == .window {
            hoveredWindow = windows.first { appKitRect(fromCG: $0.frame).contains(mouseLocation) }
        }
        redrawAll()
    }

    private func redrawAll() {
        overlays.forEach { $0.selectionView.needsDisplay = true }
    }

    private func finish(_ result: SelectionResult?) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        completion(result)
    }
}

final class SelectionWindow: NSWindow {
    let selectionView: SelectionView

    init(screen: NSScreen, controller: SelectionController, frozen: Capture?) {
        selectionView = SelectionView(screen: screen, controller: controller, frozen: frozen)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
