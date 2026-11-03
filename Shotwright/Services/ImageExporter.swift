import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageExporter {
    /// Encodes the image, tagging Retina captures with 144 DPI so they open at their point size.
    static func encode(_ image: CGImage, format: ImageFormat, scale: CGFloat) -> Data? {
        var image = image
        var dpi = 72 * scale
        if !AppSettings.saveRetina, scale > 1, let downscaled = downscale(image, by: scale) {
            image = downscaled
            dpi = 72
        }
        let type: UTType = switch format {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func filename(for date: Date, format: ImageFormat = AppSettings.fileFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Shotwright \(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Saves to the configured folder and returns the file's URL. A capture that was already
    /// saved is written back to the same file, so saving twice doesn't make a duplicate.
    @MainActor
    @discardableResult
    static func save(_ capture: Capture) throws -> URL {
        if let savedURL = capture.savedURL, FileManager.default.fileExists(atPath: savedURL.path) {
            try write(capture, to: savedURL)
            return savedURL
        }
        let url = uniqueURL(in: try SaveFolder.writableURL(), filename: filename(for: capture.date))
        try write(capture, to: url)
        capture.savedURL = url
        return url
    }

    /// `filename` in `folder`, numbered ("… 2.png") if a file by that name exists. File names
    /// only go down to the second, so two captures in the same second would otherwise collide.
    static func uniqueURL(in folder: URL, filename: String) -> URL {
        let first = folder.appendingPathComponent(filename)
        let stem = first.deletingPathExtension().lastPathComponent
        let ext = first.pathExtension
        var url = first
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return url
    }

    @MainActor
    static func write(_ capture: Capture, to url: URL) throws {
        let format = ImageFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() } ?? AppSettings.fileFormat
        guard let data = encode(capture.image, format: format, scale: capture.scale) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    /// A PNG in the temp folder, used for drag and drop out of Quick Access.
    @MainActor
    static func temporaryFile(for capture: Capture) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(capture.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename(for: capture.date, format: .png))
        guard let data = encode(capture.image, format: .png, scale: capture.scale) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func downscale(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let width = Int(CGFloat(image.width) / scale)
        let height = Int(CGFloat(image.height) / scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
