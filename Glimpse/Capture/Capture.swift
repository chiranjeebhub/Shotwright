import AppKit

/// One screenshot plus the metadata needed to save, copy and re-edit it.
@MainActor
final class Capture: ObservableObject, Identifiable {
    let id = UUID()
    let date = Date()
    /// Pixels per point of the display it was taken on (2 on Retina).
    let scale: CGFloat
    @Published var image: CGImage
    var savedURL: URL?

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }

    /// Size in points, used for on-screen layout and Retina-aware export.
    var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

/// Recent captures shown in the menu bar dropdown (in memory only).
@MainActor
final class CaptureHistory: ObservableObject {
    static let shared = CaptureHistory()
    @Published private(set) var items: [Capture] = []

    func add(_ capture: Capture) {
        items.insert(capture, at: 0)
        if items.count > 8 { items.removeLast(items.count - 8) }
    }
}

extension Capture {
    /// Crops to `rect`, given in local AppKit coordinates of a screen `screenHeight` points tall.
    func cropped(to rect: CGRect, screenHeight: CGFloat) throws -> Capture {
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: (screenHeight - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard let cropped = image.cropping(to: pixelRect) else { throw CaptureError.cropFailed }
        return Capture(image: cropped, scale: scale)
    }
}
