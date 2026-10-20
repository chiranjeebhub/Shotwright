import SwiftUI

/// The menu bar dropdown. Uses the `.window` MenuBarExtra style so it can show
/// icons, shortcuts and a strip of recent captures, while still looking like a native menu.
struct MenuBarView: View {
    @ObservedObject private var history = CaptureHistory.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRow("Capture Area", symbol: "plus.viewfinder", shortcut: "⌥⇧4") { run { $0.captureArea() } }
            MenuRow("Capture Window", symbol: "macwindow", shortcut: "⌥⇧5") { run { $0.captureWindow() } }
            MenuRow("Capture Fullscreen", symbol: "arrow.up.left.and.arrow.down.right", shortcut: "⌥⇧3") { run { $0.captureFullscreen() } }
            MenuRow("Capture Previous Area", symbol: "arrow.counterclockwise", shortcut: "⌥⇧6") { run { $0.capturePreviousArea() } }
            MenuDivider()
            MenuRow("Capture Text (OCR)", symbol: "text.viewfinder", shortcut: "⌥⇧2") { run { $0.captureText() } }
            MenuRow("Scrolling Capture", symbol: "arrow.down.to.line.compact", shortcut: "Later", isEnabled: false) {}
            MenuRow("Record Screen / GIF", symbol: "record.circle", shortcut: "Later", isEnabled: false) {}

            if !history.items.isEmpty {
                MenuDivider()
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                HStack(spacing: 6) {
                    ForEach(history.items.prefix(4)) { capture in
                        Button {
                            closeMenu()
                            EditorWindowController.open(capture)
                        } label: {
                            Image(decorative: capture.image, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help("Open in editor")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 6)
            }

            MenuDivider()
            MenuRow("Open Screenshots Folder", symbol: "folder") {
                closeMenu()
                NSWorkspace.shared.open(AppSettings.saveDirectory)
            }
            MenuRow("Settings…", symbol: "gearshape", shortcut: "⌘,") {
                closeMenu()
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            MenuRow("Quit Glimpse", symbol: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .padding(5)
        .frame(width: 300)
    }

    private func run(_ action: @escaping @MainActor (CaptureCoordinator) -> Void) {
        closeMenu()
        Task { @MainActor in
            // Let the menu window disappear before the screen is frozen.
            try? await Task.sleep(for: .milliseconds(150))
            action(CaptureCoordinator.shared)
        }
    }

    private func closeMenu() {
        NSApp.windows.first { $0.className.contains("MenuBarExtra") && $0.isVisible }?.orderOut(nil)
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    let shortcut: String?
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, symbol: String, shortcut: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .frame(width: 16)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(highlighted ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .onHover { isHovered = $0 }
    }

    private var highlighted: Bool { isHovered && isEnabled }
}

private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 9).padding(.vertical, 5)
    }
}
