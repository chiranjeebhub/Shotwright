import SwiftUI
import UniformTypeIdentifiers

struct QuickAccessCard: View {
    @ObservedObject var capture: Capture
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: QuickAccessManager.cardSize.width, height: QuickAccessManager.cardSize.height)
                .clipped()

            if isHovered {
                Color.black.opacity(0.55)

                VStack(spacing: 8) {
                    PillButton(title: "Copy") {
                        Clipboard.copy(capture)
                        Toast.show("Copied to clipboard")
                        close()
                    }
                    PillButton(title: "Save") { save() }
                }

                VStack {
                    HStack {
                        CornerButton(symbol: "xmark", label: "Close") { close() }
                        Spacer()
                        CornerButton(symbol: "pin", label: "Pin to screen") {
                            PinnedImageWindow.pin(capture)
                            close()
                        }
                    }
                    Spacer()
                    HStack {
                        CornerButton(symbol: "pencil", label: "Annotate") {
                            EditorWindowController.open(capture)
                            close()
                        }
                        Spacer()
                        CornerButton(symbol: "icloud.and.arrow.up", label: "Upload and copy link") {
                            Toast.show("Cloud upload is coming in a later version")
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: QuickAccessManager.cardSize.width, height: QuickAccessManager.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onTapGesture(count: 2) {
            EditorWindowController.open(capture)
            close()
        }
        .onDrag {
            guard let url = try? ImageExporter.temporaryFile(for: capture),
                  let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
            provider.suggestedName = url.lastPathComponent
            return provider
        }
        .contextMenu {
            Button("Copy") { Clipboard.copy(capture); close() }
            Button("Save") { save() }
            Button("Annotate") { EditorWindowController.open(capture); close() }
            Button("Pin to Screen") { PinnedImageWindow.pin(capture); close() }
            Divider()
            Button("Close") { close() }
        }
    }

    private func save() {
        do {
            let url = try ImageExporter.save(capture)
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            close()
        } catch {
            CaptureCoordinator.shared.present(error)
        }
    }

    private func close() {
        QuickAccessManager.shared.dismiss(capture)
    }
}

private struct PillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.11))
                .frame(width: 104, height: 30)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
    }
}

private struct CornerButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(white: 0.11))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
