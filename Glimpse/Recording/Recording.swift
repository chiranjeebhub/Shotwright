import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum RecordingFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case gif = "GIF"

    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
}

/// Recording preferences, set from the recording bar and remembered between recordings.
enum RecordingSettings {
    static let formatKey = "recordingFormat"
    static let showCursorKey = "recordingShowsCursor"

    static var format: RecordingFormat {
        RecordingFormat(rawValue: UserDefaults.standard.string(forKey: formatKey) ?? "") ?? .mp4
    }

    static var showCursor: Bool {
        UserDefaults.standard.object(forKey: showCursorKey) as? Bool ?? true
    }
}

/// A finished screen recording. It lives in a temp folder until it's saved.
@MainActor
final class Recording: ObservableObject, Identifiable {
    let id = UUID()
    let date: Date
    let format: RecordingFormat
    let duration: TimeInterval
    let thumbnail: CGImage?
    @Published private(set) var url: URL
    private(set) var savedURL: URL?

    init(url: URL, date: Date, format: RecordingFormat, duration: TimeInterval, thumbnail: CGImage?) {
        self.url = url
        self.date = date
        self.format = format
        self.duration = duration
        self.thumbnail = thumbnail
    }

    var durationText: String { Self.timeText(duration) }

    static func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func filename(for date: Date, format: RecordingFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Glimpse Recording \(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Moves the file into the screenshots folder.
    @discardableResult
    func save() throws -> URL {
        if let savedURL { return savedURL }
        let folder = AppSettings.saveDirectory
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = url.deletingPathExtension().lastPathComponent
            destination = folder.appendingPathComponent("\(stem) \(counter).\(format.fileExtension)")
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: destination)
        url = destination
        savedURL = destination
        return destination
    }

    /// Copies the file, so it pastes into Finder, Slack, Mail and so on. GIFs also go
    /// on the pasteboard as GIF data, for apps that take images rather than files.
    func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        if format == .gif, let data = try? Data(contentsOf: url) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
    }

    /// Deletes the file unless it was saved.
    func discard() {
        guard savedURL == nil else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

enum RecordingExporter {
    static let gifFrameRate = 15.0
    /// Longest side of a GIF in pixels; full Retina resolution makes huge files.
    static let gifMaxDimension: CGFloat = 1200

    /// A fresh temp folder per recording, so the file keeps its final name for drag and drop.
    static func temporaryURL(for date: Date, format: RecordingFormat) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Glimpse Recordings", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(Recording.filename(for: date, format: format))
    }

    /// Turns the recorded MP4 into the requested format and wraps it in a `Recording`.
    @MainActor
    static func finish(videoURL: URL, format: RecordingFormat, date: Date, pointScale: CGFloat) async throws -> Recording {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let thumbnail = try? await frame(of: asset, at: .zero, maxDimension: 600)

        guard format == .gif else {
            return Recording(url: videoURL, date: date, format: .mp4, duration: duration, thumbnail: thumbnail)
        }
        let gifURL = videoURL.deletingPathExtension().appendingPathExtension(RecordingFormat.gif.fileExtension)
        try await makeGIF(from: asset, duration: duration, pointScale: pointScale, to: gifURL)
        try? FileManager.default.removeItem(at: videoURL)
        return Recording(url: gifURL, date: date, format: .gif, duration: duration, thumbnail: thumbnail)
    }

    private static func frame(of asset: AVAsset, at time: CMTime, maxDimension: CGFloat) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        return try await generator.image(at: time).image
    }

    /// Samples the video at `gifFrameRate` and writes a looping GIF, at point size (not
    /// Retina) and capped at `gifMaxDimension`.
    private static func makeGIF(from asset: AVAsset, duration: TimeInterval, pointScale: CGFloat, to url: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RecordingError.gifFailed }
        let pixelSize = try await track.load(.naturalSize)
        var size = CGSize(width: pixelSize.width / max(pointScale, 1), height: pixelSize.height / max(pointScale, 1))
        let longest = max(size.width, size.height)
        if longest > gifMaxDimension {
            size = CGSize(width: size.width * gifMaxDimension / longest, height: size.height * gifMaxDimension / longest)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = size
        let tolerance = CMTime(seconds: 0.5 / gifFrameRate, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let frameCount = max(1, Int((duration * gifFrameRate).rounded(.down)))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw RecordingError.gifFailed
        }
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0] as [CFString: Any],
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let delay = 1 / gifFrameRate
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ] as [CFString: Any],
        ]

        var previous: CGImage?
        for index in 0 ..< frameCount {
            let time = CMTime(seconds: Double(index) / gifFrameRate, preferredTimescale: 600)
            // A frame that fails to decode repeats the previous one so the timing stays right.
            let image = (try? await generator.image(at: time).image) ?? previous
            guard let image else { throw RecordingError.gifFailed }
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            previous = image
        }
        guard CGImageDestinationFinalize(destination) else { throw RecordingError.gifFailed }
    }
}
