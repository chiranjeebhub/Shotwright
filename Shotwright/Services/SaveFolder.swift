import AppKit

/// The folder screenshots and recordings are saved to.
///
/// Shotwright runs in the App Sandbox, so it can only write to a folder the user picked in an
/// open panel. The pick is kept as a security-scoped bookmark, and access to it stays open for
/// the life of the app. Until a folder is picked, the first save asks for one (Desktop preselected).
@MainActor
enum SaveFolder {
    private static let bookmarkKey = "saveDirectoryBookmark"
    private static var accessedURL: URL?

    /// The folder to save into. Without a usable bookmark this is where saves will go once access is granted.
    static var url: URL {
        accessedURL ?? storedPathURL ?? desktop
    }

    /// Re-opens access to the bookmarked folder. Call once at launch.
    static func restoreAccess() {
        guard accessedURL == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else { return }
        accessedURL = url
        if isStale { store(url) }
    }

    /// Returns the folder, ready to write to. In the sandbox with no folder picked yet, asks for one;
    /// throws `CocoaError(.userCancelled)` if the user cancels.
    static func writableURL() throws -> URL {
        restoreAccess()
        if accessedURL != nil || !isSandboxed { return url }
        guard choose(message: "Choose where Shotwright saves your screenshots and recordings. You can change this later in Settings.") else {
            throw CocoaError(.userCancelled)
        }
        return url
    }

    /// Shows a folder picker and, if the user picks one, saves to it from now on.
    @discardableResult
    static func choose(message: String? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = message ?? ""
        panel.directoryURL = url
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let picked = panel.url else { return false }

        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = picked.startAccessingSecurityScopedResource() ? picked : nil
        store(picked)
        return true
    }

    /// Opens the folder in Finder.
    static func reveal() {
        restoreAccess()
        NSWorkspace.shared.open(url)
    }

    private static func store(_ url: URL) {
        let defaults = UserDefaults.standard
        defaults.set(url.path, forKey: SettingsKey.saveDirectory)
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(data, forKey: bookmarkKey)
        }
    }

    private static var storedPathURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: SettingsKey.saveDirectory), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The user's real Desktop. Inside the sandbox, FileManager would return the container's copy.
    private static var desktop: URL {
        let home = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
    }

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
