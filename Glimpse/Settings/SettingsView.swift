import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            QuickAccessSettings()
                .tabItem { Label("Quick Access", systemImage: "rectangle.inset.bottomleft.filled") }
            AnnotateSettings()
                .tabItem { Label("Annotate", systemImage: "pencil.tip") }
            CloudSettings()
                .tabItem { Label("Cloud", systemImage: "icloud") }
        }
        .frame(width: 620)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.saveDirectory) private var saveDirectory = ""
    @AppStorage(SettingsKey.fileFormat) private var fileFormat = ImageFormat.png.rawValue
    @AppStorage(SettingsKey.saveRetina) private var saveRetina = true
    @AppStorage(SettingsKey.showQuickAccess) private var showQuickAccess = true
    @AppStorage(SettingsKey.copyToClipboard) private var copyToClipboard = false
    @AppStorage(SettingsKey.autoSave) private var autoSave = false
    @AppStorage(SettingsKey.playSound) private var playSound = true
    @AppStorage(SettingsKey.includeCursor) private var includeCursor = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                LabeledContent("Save screenshots to") {
                    HStack {
                        Text(displayPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("File format", selection: $fileFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Save at Retina resolution (@2x)", isOn: $saveRetina)
            }

            Section("After capture") {
                Toggle("Show Quick Access overlay", isOn: $showQuickAccess)
                Toggle("Copy to clipboard", isOn: $copyToClipboard)
                Toggle("Save to folder automatically", isOn: $autoSave)
                Toggle("Play shutter sound", isOn: $playSound)
            }

            Section {
                Toggle("Start Glimpse at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("Include cursor in screenshots", isOn: $includeCursor)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
    }

    private var displayPath: String {
        (AppSettings.saveDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ShortcutSettings: View {
    private let shortcuts: [(String, String)] = [
        ("Capture Area", "⌥⇧4"),
        ("Capture Window", "⌥⇧5"),
        ("Capture Fullscreen", "⌥⇧3"),
        ("Capture Previous Area", "⌥⇧6"),
        ("Capture Text (OCR)", "⌥⇧2"),
        ("Scrolling Capture", "⌥⇧8"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts, id: \.0) { shortcut in
                    LabeledContent(shortcut.0) {
                        Text(shortcut.1)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    }
                }
            } footer: {
                Text("Custom shortcuts are coming in a later version.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct QuickAccessSettings: View {
    @AppStorage(SettingsKey.showQuickAccess) private var showQuickAccess = true

    var body: some View {
        Form {
            Toggle("Show Quick Access overlay after capture", isOn: $showQuickAccess)
            Text("Thumbnails stack in the bottom-left corner. Hover for Copy and Save, double-click to annotate, or drag one into any app.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 200)
    }
}

private struct AnnotateSettings: View {
    var body: some View {
        Form {
            Text("Arrow, shapes, pen, highlighter, text, numbered counters, pixelate and crop are available in the editor. Editor preferences are coming in a later version.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 200)
    }
}

private struct CloudSettings: View {
    var body: some View {
        Form {
            Text("Upload and share links are coming in a later version.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 200)
    }
}
