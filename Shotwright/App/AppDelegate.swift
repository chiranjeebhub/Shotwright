import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.registerDefaults()
        SaveFolder.restoreAccess()
        Updater.start()
        PermissionManager.requestOnFirstLaunch()
    }
}
