import AppKit

enum PermissionManager {
    /// Returns true when screen recording access is granted; otherwise explains how to grant it.
    @MainActor
    static func ensureScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "Glimpse needs Screen Recording access"
        alert.informativeText = "Turn on Glimpse in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Glimpse."
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
