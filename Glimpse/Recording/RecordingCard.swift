import AppKit
import SwiftUI

/// The Quick Access card for a finished recording: a thumbnail with a format and length
/// badge. Hover for Copy and Save, double-click to play, or drag the file into any app.
struct RecordingCard: View {
    @ObservedObject var recording: Recording
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color.black
            if let thumbnail = recording.thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: QuickAccessManager.cardSize.width, height: QuickAccessManager.cardSize.height)
                    .clipped()
            }

            if isHovered {
                Color.black.opacity(0.55)

                VStack(spacing: 8) {
                    PillButton(title: "Copy") {
                        recording.copy()
                        Toast.show("Copied to clipboard")
                        close(keepFile: true)
                    }
                    PillButton(title: "Save") { save() }
                }

                VStack {
                    HStack {
                        CornerButton(symbol: "xmark", label: "Close") { close() }
                        Spacer()
                        CornerButton(symbol: "play.fill", label: "Play") { play() }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        CornerButton(symbol: "icloud.and.arrow.up", label: "Upload and copy link") {
                            Toast.show("Cloud upload is coming in a later version")
                        }
                    }
                }
                .padding(8)
            } else {
                VStack {
                    Spacer()
                    HStack {
                        badge
                        Spacer()
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
        .onTapGesture(count: 2) { play() }
        .onDrag {
            let provider = NSItemProvider(contentsOf: recording.url) ?? NSItemProvider()
            provider.suggestedName = recording.url.lastPathComponent
            return provider
        }
        .contextMenu {
            Button("Copy") { recording.copy(); close(keepFile: true) }
            Button("Save") { save() }
            Button("Play") { play() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }
            Divider()
            Button("Close") { close() }
        }
    }

    private var badge: some View {
        HStack(spacing: 4) {
            Image(systemName: recording.format == .gif ? "photo.stack" : "video.fill")
            Text("\(recording.format.rawValue) · \(recording.durationText)")
        }
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color(white: 0.08, opacity: 0.85)))
    }

    private func play() {
        NSWorkspace.shared.open(recording.url)
    }

    private func save() {
        do {
            let url = try recording.save()
            Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            close()
        } catch {
            CaptureCoordinator.shared.present(error)
        }
    }

    /// Closing an unsaved recording deletes it, like closing an unsaved screenshot.
    /// After Copy the temp file stays, since the pasteboard points at it.
    private func close(keepFile: Bool = false) {
        if !keepFile { recording.discard() }
        QuickAccessManager.shared.dismiss(recording)
    }
}
