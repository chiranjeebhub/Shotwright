import AppKit
import ScreenCaptureKit
import SwiftUI

/// Runs a scrolling capture: keeps grabbing the selected area while the user scrolls
/// the content under it, and stitches the frames into one tall screenshot.
@MainActor
final class ScrollingCaptureSession {
    private static var current: ScrollingCaptureSession?
    static var isActive: Bool { current != nil }

    /// `rect` is in the screen's local AppKit coordinates.
    static func start(rect: CGRect, on screen: NSScreen, completion: @escaping (Capture) -> Void) {
        guard current == nil else { return }
        let session = ScrollingCaptureSession(rect: rect, screen: screen, completion: completion)
        current = session
        session.begin()
    }

    private let rect: CGRect
    private let screen: NSScreen
    private let completion: (Capture) -> Void
    private let model = ScrollingCaptureModel()
    private let stitcher = ScrollStitcher()

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var loop: Task<Void, Never>?
    private var scale: CGFloat = 1

    private init(rect: CGRect, screen: NSScreen, completion: @escaping (Capture) -> Void) {
        self.rect = rect
        self.screen = screen
        self.completion = completion
    }

    /// The selection in global AppKit coordinates.
    private var globalRect: CGRect { rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) }

    private func begin() {
        showWindows()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53: // Esc
                self?.cancel()
                return nil
            case 36, 76: // Return, Enter
                self?.finish()
                return nil
            default:
                return event
            }
        }

        loop = Task { [weak self, rect, screen] in
            do {
                let source = try await CaptureService.repeatingSource(for: rect, on: screen)
                self?.scale = source.scale
                var lastPreview = Date.distantPast
                while !Task.isCancelled {
                    let frame = try await SCScreenshotManager.captureImage(contentFilter: source.filter, configuration: source.configuration)
                    guard let self, !Task.isCancelled else { return }
                    let update = await stitcher.add(frame)
                    model.lostTrack = update == .lostTrack
                    if update == .appended || update == .reachedLimit {
                        model.pixelSize = await stitcher.pixelSize
                        if Date().timeIntervalSince(lastPreview) > 0.25 {
                            lastPreview = Date()
                            model.preview = await stitcher.makeImage(maxWidth: 280)
                        }
                    }
                    if update == .reachedLimit {
                        Toast.show("Maximum height reached")
                        finish()
                        return
                    }
                    try await Task.sleep(for: .milliseconds(60))
                }
            } catch is CancellationError {
            } catch {
                self?.close()
                CaptureCoordinator.shared.present(error)
            }
        }
    }

    func finish() {
        guard !model.isFinishing else { return }
        model.isFinishing = true
        loop?.cancel()
        Task {
            // The stitcher is an actor, so this waits for any frame still being added.
            let image = await stitcher.makeImage()
            close()
            if let image {
                completion(Capture(image: image, scale: scale))
            }
        }
    }

    func cancel() {
        loop?.cancel()
        close()
    }

    private func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if Self.current === self { Self.current = nil }
    }

    // MARK: Windows

    private func showWindows() {
        let area = globalRect
        let visible = screen.visibleFrame

        // Border just outside the area; it lets clicks and scrolls through.
        let border = OverlayPanel(frame: area.insetBy(dx: -3, dy: -3))
        border.ignoresMouseEvents = true
        border.contentView = ScrollingCaptureBorderView()
        windows.append(border)

        // Controls below the area, else above it, else inside its bottom edge.
        let hudSize = CGSize(width: 400, height: 56)
        var hudOrigin = CGPoint(x: area.midX - hudSize.width / 2, y: area.minY - hudSize.height - 14)
        if hudOrigin.y < visible.minY { hudOrigin.y = area.maxY + 14 }
        if hudOrigin.y + hudSize.height > visible.maxY { hudOrigin.y = area.minY + 14 }
        hudOrigin.x = min(max(hudOrigin.x, visible.minX + 8), visible.maxX - hudSize.width - 8)
        let hud = OverlayPanel(frame: CGRect(origin: hudOrigin, size: hudSize))
        hud.acceptsKeys = true
        hud.contentView = NSHostingView(rootView: ScrollingCaptureHUD(
            model: model,
            onCancel: { [weak self] in self?.cancel() },
            onDone: { [weak self] in self?.finish() }
        ))
        windows.append(hud)

        // Live preview beside the area, if there's room on either side.
        let previewWidth: CGFloat = 150
        let previewHeight = min(area.height, visible.height - 16)
        var previewX: CGFloat?
        if area.maxX + 14 + previewWidth <= visible.maxX {
            previewX = area.maxX + 14
        } else if area.minX - 14 - previewWidth >= visible.minX {
            previewX = area.minX - 14 - previewWidth
        }
        if let previewX, previewHeight > 80 {
            let y = min(max(area.maxY - previewHeight, visible.minY + 8), visible.maxY - previewHeight - 8)
            let preview = OverlayPanel(frame: CGRect(x: previewX, y: y, width: previewWidth, height: previewHeight))
            preview.ignoresMouseEvents = true
            preview.contentView = NSHostingView(rootView: ScrollingCapturePreview(model: model))
            windows.append(preview)
        }

        windows.forEach { $0.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
        hud.makeKey()
    }
}

/// A borderless, transparent panel that floats above other apps without taking focus
/// from the content being scrolled (scroll events still go to the window under the cursor).
private final class OverlayPanel: NSPanel {
    var acceptsKeys = false

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { acceptsKeys }
}

private final class ScrollingCaptureBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let outer = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        outer.lineWidth = 1
        outer.stroke()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        border.lineWidth = 2
        border.setLineDash([6, 4], count: 2, phase: 0)
        border.stroke()
    }
}

extension CaptureService {
    /// A filter and configuration for grabbing `rect` (screen-local AppKit coordinates)
    /// over and over, without the cursor or Shotwright's own windows.
    @MainActor
    static func repeatingSource(for rect: CGRect, on screen: NSScreen) async throws -> (filter: SCContentFilter, configuration: SCStreamConfiguration, scale: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        // The cursor would move with the mouse rather than the content and break matching.
        config.showsCursor = false
        config.captureResolution = .best
        return (filter, config, scale)
    }
}
