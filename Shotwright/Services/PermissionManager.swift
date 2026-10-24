import AppKit

enum PermissionManager {
    private static let requestedKey = "didRequestScreenCaptureAccess"

    /// Shows the system Screen Recording prompt, but only the first time Shotwright ever runs.
    /// macOS keeps re-showing that prompt whenever it is asked again, even when access is already
    /// on, so every later check goes through our own alert instead.
    @MainActor
    static func requestOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !CGPreflightScreenCaptureAccess(), !defaults.bool(forKey: requestedKey) else { return }
        defaults.set(true, forKey: requestedKey)
        CGRequestScreenCaptureAccess()
    }

    /// Returns true when screen recording access is granted; otherwise explains how to grant it.
    @MainActor
    static func ensureScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }

        let alert = NSAlert()
        alert.messageText = "Shotwright needs Screen Recording access"
        alert.addButton(withTitle: "Open System Settings")
        if canResetPermission {
            // A switch that shows on but doesn't work belongs to an earlier copy of Shotwright
            // signed differently (another build or install). Resetting drops that stale entry.
            alert.informativeText = "Turn on Shotwright in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Shotwright.\n\nIf it is already on, click Reset Permission, turn Shotwright on again when asked, and reopen Shotwright."
            alert.addButton(withTitle: "Reset Permission")
        } else {
            alert.informativeText = "Turn on Shotwright in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Shotwright.\n\nIf it is already on, remove Shotwright from that list with the − button, add it again, and reopen Shotwright."
        }
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSettings()
        case .alertSecondButtonReturn where canResetPermission:
            resetPermission()
            CGRequestScreenCaptureAccess()
            openSettings()
        default:
            break
        }
        return false
    }

    /// The sandboxed App Store build can't run tccutil.
    private static var canResetPermission: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    private static func resetPermission() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        try? process.run()
        process.waitUntilExit()
    }

    private static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
