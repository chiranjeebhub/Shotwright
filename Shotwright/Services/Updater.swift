import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Sparkle auto-updates for the direct-download build. The App Store build doesn't link Sparkle,
/// so there this does nothing and the store handles updates.
@MainActor
enum Updater {
    #if canImport(Sparkle)
    private static var controller: SPUStandardUpdaterController?
    #endif

    /// True when this build can update itself (direct download, with a feed and signing key set).
    static var isAvailable: Bool {
        #if canImport(Sparkle)
        controller != nil
        #else
        false
        #endif
    }

    /// Starts the background update checks. Call once at launch.
    static func start() {
        #if canImport(Sparkle)
        // Sparkle shows an error at launch if either is missing, so local builds without them skip updates.
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    static func checkForUpdates() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }
}
