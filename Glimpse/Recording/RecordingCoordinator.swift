import AppKit
import ScreenCaptureKit

/// What a recording covers: an area of one screen (local AppKit coordinates) or one window.
enum RecordingTarget {
    case area(CGRect, NSScreen)
    case window(SCWindow)

    /// The recorded region in global AppKit coordinates.
    @MainActor
    var globalFrame: CGRect {
        switch self {
        case let .area(rect, screen): rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        case let .window(window): appKitRect(fromCG: window.frame)
        }
    }

    @MainActor
    var screen: NSScreen {
        switch self {
        case let .area(_, screen): return screen
        case .window:
            let center = NSPoint(x: globalFrame.midX, y: globalFrame.midY)
            return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.underMouse
        }
    }
}

/// Runs a recording from start to finish: area or window selection (via the capture
/// overlay), the recording bar, the stream itself, then export and Quick Access.
@MainActor
final class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    enum Phase { case idle, ready, starting, recording, finishing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var target: RecordingTarget?
    private var recorder: ScreenRecorder?
    private var format: RecordingFormat = .mp4
    private var pointScale: CGFloat = 2
    private var startDate = Date()
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    private var ticker: Timer?
    private var bar: RecordingBarPanel?
    private var border: RecordingBorderWindow?
    private var keyMonitor: Any?

    var isRecording: Bool { phase == .recording }

    /// Menu and hotkey entry point: picks what to record, starts it, or stops it.
    func toggle() {
        switch phase {
        case .idle: CaptureCoordinator.shared.selectRecordingTarget()
        case .ready: start()
        case .recording: stop()
        case .starting, .finishing: break
        }
    }

    /// Called with the area or window picked in the capture overlay. Shows the recording bar.
    func prepare(_ selection: SelectionResult) {
        guard phase == .idle else { return }
        switch selection {
        case let .area(rect, screen, _): target = .area(rect, screen)
        case let .window(window): target = .window(window)
        }
        phase = .ready
        showChrome()
    }

    func start() {
        guard phase == .ready, let target else { return }
        phase = .starting
        removeKeyMonitor()
        format = RecordingSettings.format
        startDate = Date()
        Task {
            do {
                let recorder = try await makeRecorder(for: target)
                recorder.onStop = { _ in RecordingCoordinator.shared.stop() }
                try await recorder.start()
                self.recorder = recorder
                startDate = Date()
                pausedTotal = 0
                pausedAt = nil
                isPaused = false
                elapsed = 0
                phase = .recording
                ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                    Task { @MainActor in RecordingCoordinator.shared.tick() }
                }
            } catch {
                reset()
                CaptureCoordinator.shared.present(error)
            }
        }
    }

    func togglePause() {
        guard phase == .recording, let recorder else { return }
        if let pausedAt {
            pausedTotal += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
            recorder.resume()
        } else {
            pausedAt = Date()
            recorder.pause()
        }
        isPaused = pausedAt != nil
        tick()
    }

    func stop() { finish(keep: true) }

    /// Stops and throws the recording away.
    func discard() { finish(keep: false) }

    /// Closes the bar before recording has started.
    func cancel() {
        guard phase == .ready else { return }
        reset()
    }

    private func tick() {
        let pausedNow = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        elapsed = Date().timeIntervalSince(startDate) - pausedTotal - pausedNow
    }

    private func finish(keep: Bool) {
        guard phase == .recording, let recorder else { return }
        phase = .finishing
        hideChrome()
        let format = format
        let date = startDate
        let pointScale = pointScale
        Task {
            defer { reset() }
            do {
                let videoURL = try await recorder.stop()
                guard keep else {
                    try? FileManager.default.removeItem(at: videoURL.deletingLastPathComponent())
                    return
                }
                if format == .gif { Toast.show("Making GIF…") }
                let recording = try await RecordingExporter.finish(videoURL: videoURL, format: format, date: date, pointScale: pointScale)
                deliver(recording)
            } catch RecordingError.noFrames {
                try? FileManager.default.removeItem(at: recorder.outputURL.deletingLastPathComponent())
            } catch {
                CaptureCoordinator.shared.present(error)
            }
        }
    }

    private func deliver(_ recording: Recording) {
        // With Quick Access off there'd be no way to get the file, so save it.
        if AppSettings.autoSave || !AppSettings.showQuickAccess {
            do { try recording.save() } catch { CaptureCoordinator.shared.present(error) }
        }
        if AppSettings.copyToClipboard { recording.copy() }
        if AppSettings.showQuickAccess {
            QuickAccessManager.shared.show(recording)
        } else if let url = recording.savedURL {
            Toast.show("Recording saved to \(url.deletingLastPathComponent().lastPathComponent)")
        }
    }

    private func reset() {
        ticker?.invalidate()
        ticker = nil
        hideChrome()
        recorder = nil
        target = nil
        isPaused = false
        pausedAt = nil
        elapsed = 0
        phase = .idle
    }

    // MARK: Stream setup

    private func makeRecorder(for target: RecordingTarget) async throws -> ScreenRecorder {
        let config = SCStreamConfiguration()
        let filter: SCContentFilter
        let size: CGSize
        switch target {
        case let .area(rect, screen):
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
                throw CaptureError.displayNotFound
            }
            // Our own bar and border stay out of the video.
            let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            config.sourceRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
            size = rect.size
        case let .window(window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = window.frame.size
        }
        pointScale = CGFloat(filter.pointPixelScale)
        // Video encoders want even dimensions.
        config.width = max(2, Int(size.width * pointScale) / 2 * 2)
        config.height = max(2, Int(size.height * pointScale) / 2 * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: format == .gif ? 30 : 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = RecordingSettings.showCursor
        config.queueDepth = 6
        let url = try RecordingExporter.temporaryURL(for: startDate, format: .mp4)
        return try ScreenRecorder(filter: filter, configuration: config, outputURL: url)
    }

    // MARK: Bar and border

    private func showChrome() {
        guard let target else { return }
        if case let .area(rect, screen) = target {
            border = RecordingBorderWindow(frame: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
            border?.orderFrontRegardless()
        }
        let bar = RecordingBarPanel(coordinator: self)
        bar.setFrameOrigin(barOrigin(for: bar.frame.size, around: target))
        NSApp.activate(ignoringOtherApps: true)
        bar.makeKeyAndOrderFront(nil)
        self.bar = bar

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, phase == .ready else { return event }
            switch event.keyCode {
            case 53: cancel(); return nil // Esc
            case 36, 76: start(); return nil // Return, Enter
            default: return event
            }
        }
    }

    private func hideChrome() {
        removeKeyMonitor()
        bar?.orderOut(nil)
        bar = nil
        border?.orderOut(nil)
        border = nil
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Centered under the recorded region; inside its bottom edge when there's no room below.
    private func barOrigin(for size: CGSize, around target: RecordingTarget) -> NSPoint {
        let region = target.globalFrame
        let visible = target.screen.visibleFrame
        var origin = NSPoint(x: region.midX - size.width / 2, y: region.minY - size.height)
        if origin.y < visible.minY { origin.y = max(visible.minY, region.minY) + 8 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        return origin
    }
}
