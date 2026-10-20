import AppKit

enum Clipboard {
    @MainActor
    static func copy(_ capture: Capture) {
        copy(capture.image, scale: capture.scale)
    }

    static func copy(_ image: CGImage, scale: CGFloat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        pasteboard.writeObjects([NSImage(cgImage: image, size: size)])
        if let png = ImageExporter.encode(image, format: .png, scale: scale) {
            pasteboard.setData(png, forType: .png)
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
