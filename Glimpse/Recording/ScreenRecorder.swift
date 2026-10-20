import AVFoundation
import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case noFrames
    case writerFailed(Error?)
    case gifFailed

    var errorDescription: String? {
        switch self {
        case .noFrames: "Nothing was recorded."
        case let .writerFailed(error): "Couldn't write the recording." + (error.map { " \($0.localizedDescription)" } ?? "")
        case .gifFailed: "Couldn't create the GIF."
        }
    }
}

/// Streams a display region or a single window into an MP4 with ScreenCaptureKit and
/// AVAssetWriter. Supports pausing: paused time is cut out of the file.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let outputURL: URL
    /// Called on the main actor if the stream stops by itself, e.g. the recorded window closed.
    var onStop: (@MainActor (Error) -> Void)?

    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue = DispatchQueue(label: "com.glimpse.recorder")
    private var stream: SCStream?

    // Only touched on `queue`.
    private var sessionStarted = false
    private var isPaused = false
    private var pausedAt: CMTime?
    private var pauseOffset = CMTime.zero
    private var lastFrameTime = CMTime.zero

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL) throws {
        self.filter = filter
        self.configuration = configuration
        self.outputURL = outputURL
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let width = configuration.width
        let height = configuration.height
        // The hardware H.264 encoder tops out at 4096 × 2304; bigger (5K/6K) areas need HEVC.
        let codec: AVVideoCodecType = (width > 4096 || height > 2304) ? .hevc : .h264
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 5,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 120,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw RecordingError.writerFailed(nil) }
        writer.add(input)
        super.init()
    }

    func start() async throws {
        guard writer.startWriting() else { throw RecordingError.writerFailed(writer.error) }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }

    func pause() {
        queue.async {
            guard !self.isPaused else { return }
            self.isPaused = true
            self.pausedAt = Self.now
        }
    }

    func resume() {
        queue.async {
            guard self.isPaused, let pausedAt = self.pausedAt else { return }
            self.pauseOffset = CMTimeAdd(self.pauseOffset, CMTimeSubtract(Self.now, pausedAt))
            self.isPaused = false
            self.pausedAt = nil
        }
    }

    /// Stops capturing and finishes the file. Returns its URL.
    func stop() async throws -> URL {
        try? await stream?.stopCapture()
        stream = nil
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.sessionStarted else {
                    self.writer.cancelWriting()
                    continuation.resume(throwing: RecordingError.noFrames)
                    return
                }
                // ScreenCaptureKit only sends frames when something changes, so hold the
                // last frame until the moment Stop was pressed.
                let end = CMTimeSubtract(self.pausedAt ?? Self.now, self.pauseOffset)
                self.writer.endSession(atSourceTime: CMTimeMaximum(end, self.lastFrameTime))
                self.input.markAsFinished()
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else {
                        continuation.resume(throwing: RecordingError.writerFailed(self.writer.error))
                    }
                }
            }
        }
    }

    /// ScreenCaptureKit stamps frames with the host clock.
    private static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !isPaused, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let time = CMTimeSubtract(sampleBuffer.presentationTimeStamp, pauseOffset)
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }
        guard input.isReadyForMoreMediaData, CMTimeCompare(time, lastFrameTime) > 0 || lastFrameTime == .zero else { return }
        if adaptor.append(pixelBuffer, withPresentationTime: time) {
            lastFrameTime = time
        }
    }

    /// Idle and blank frames carry no new pixels.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.onStop?(error) }
    }
}
