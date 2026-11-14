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
            alert.informativeText = "\(listHint)\n\nIf it is already on in that top list, click Reset Permission, turn Shotwright on again when asked, and reopen Shotwright."
            alert.addButton(withTitle: "Reset Permission")
        } else {
            alert.informativeText = "\(listHint)\n\nIf it is already on in that top list, remove Shotwright from it with the − button, add it again with +, and reopen Shotwright."
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

    /// macOS 15 and later split this settings page into two lists. A switch under the lower
    /// "System Audio Recording Only" list grants audio alone, so Shotwright still can't see the screen.
    private static let listHint = "Open System Settings › Privacy & Security › Screen & System Audio Recording and turn on Shotwright in the top list, \"Screen & System Audio Recording\" (use + under that list if Shotwright isn't there). The \"System Audio Recording Only\" list below it doesn't allow screen capture. Then quit and reopen Shotwright."

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
