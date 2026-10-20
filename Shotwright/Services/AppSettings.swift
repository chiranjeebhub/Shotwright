import Foundation

/// UserDefaults keys shared by `AppSettings` (reads) and `SettingsView` (@AppStorage).
enum SettingsKey {
    static let saveDirectory = "saveDirectory"
    static let fileFormat = "fileFormat"
    static let saveRetina = "saveRetina"
    static let showQuickAccess = "showQuickAccess"
    static let copyToClipboard = "copyToClipboard"
    static let autoSave = "autoSave"
    static let playSound = "playSound"
    static let includeCursor = "includeCursor"
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case heic = "HEIC"

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    static var fileFormat: ImageFormat {
        ImageFormat(rawValue: defaults.string(forKey: SettingsKey.fileFormat) ?? "") ?? .png
    }

    static var saveRetina: Bool { bool(SettingsKey.saveRetina, default: true) }
    static var showQuickAccess: Bool { bool(SettingsKey.showQuickAccess, default: true) }
    static var copyToClipboard: Bool { bool(SettingsKey.copyToClipboard, default: false) }
    static var autoSave: Bool { bool(SettingsKey.autoSave, default: false) }
    static var playSound: Bool { bool(SettingsKey.playSound, default: true) }
    static var includeCursor: Bool { bool(SettingsKey.includeCursor, default: false) }
}
