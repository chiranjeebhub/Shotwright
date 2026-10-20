import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case displayNotFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Couldn't find the display to capture."
        case .cropFailed: "Couldn't crop the selected area."
        }
    }
}

/// Thin wrapper over ScreenCaptureKit's still-image API (macOS 14+).
enum CaptureService {
    /// Captures a whole screen.
    @MainActor
    static func captureScreen(_ screen: NSScreen) async throws -> Capture {
        try await captureArea(CGRect(origin: .zero, size: screen.frame.size), on: screen)
    }

    /// Captures `rect`, given in the screen's local AppKit coordinates (origin bottom-left).
    @MainActor
    static func captureArea(_ rect: CGRect, on screen: NSScreen) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Keep our own overlays and thumbnails out of the shot.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        // ScreenCaptureKit wants a top-left origin relative to the display.
        config.sourceRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        config.showsCursor = AppSettings.includeCursor
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(image: image, scale: scale)
    }

    /// Captures a single window on its own, without anything overlapping it.
    @MainActor
    static func captureWindow(_ window: SCWindow) async throws -> Capture {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(image: image, scale: scale)
    }

    /// Normal app windows currently on screen, front-most first.
    static func selectableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownBundle = Bundle.main.bundleIdentifier
        let candidates = content.windows.filter { window in
            window.isOnScreen
                && window.windowLayer == 0
                && window.frame.width > 40 && window.frame.height > 40
                && window.owningApplication?.bundleIdentifier != ownBundle
        }
        // SCShareableContent doesn't promise z-order; CGWindowList does (front to back).
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let order = info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return candidates.sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    static var underMouse: NSScreen {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main ?? screens[0]
    }
}

/// Converts a rect in global CoreGraphics coordinates (top-left origin of the
/// primary display) to global AppKit coordinates (bottom-left origin).
func appKitRect(fromCG rect: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}
