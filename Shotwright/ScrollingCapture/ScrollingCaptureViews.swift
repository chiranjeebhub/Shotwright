import SwiftUI

@MainActor
final class ScrollingCaptureModel: ObservableObject {
    /// Size of the stitched image so far, in pixels.
    @Published var pixelSize: CGSize = .zero
    @Published var lostTrack = false
    @Published var preview: CGImage?
    @Published var isFinishing = false
}

/// The control bar shown next to the area while scrolling, in the same dark HUD
/// style as the selection hint bar and toasts.
struct ScrollingCaptureHUD: View {
    @ObservedObject var model: ScrollingCaptureModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.lostTrack ? "exclamationmark.triangle.fill" : "arrow.down.to.line.compact")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.lostTrack ? Color.orange : Color.white)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            Button("Cancel", action: onCancel)
                .buttonStyle(HUDButtonStyle(prominent: false))
            Button("Done", action: onDone)
                .buttonStyle(HUDButtonStyle(prominent: true))
                .disabled(model.isFinishing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.08, opacity: 0.85)))
    }

    private var title: String {
        if model.isFinishing { return "Stitching…" }
        return model.lostTrack ? "Lost track, scroll back a little" : "Scroll slowly to capture"
    }

    private var subtitle: String {
        guard model.pixelSize.height > 0 else { return "Return to finish · Esc to cancel" }
        return "\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height)) · Return to finish"
    }
}

private struct HUDButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color(white: 0.11) : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// A strip showing the stitched result so far, newest content at the bottom.
struct ScrollingCapturePreview: View {
    @ObservedObject var model: ScrollingCaptureModel

    var body: some View {
        GeometryReader { geometry in
            let inner = CGSize(width: geometry.size.width - 12, height: geometry.size.height - 12)
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.08, opacity: 0.85))
                if let preview = model.preview, preview.width > 0 {
                    let height = inner.width * CGFloat(preview.height) / CGFloat(preview.width)
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .frame(width: inner.width, height: height)
                        // Once it's taller than the strip, keep the latest part in view.
                        .frame(width: inner.width, height: inner.height, alignment: height > inner.height ? .bottom : .top)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Text("Preview")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}
