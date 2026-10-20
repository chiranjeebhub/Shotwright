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
        alert.informativeText = "Turn on Shotwright in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Shotwright.\n\nIf it is already on, remove Shotwright from that list with the − button, add it again, and reopen Shotwright."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
