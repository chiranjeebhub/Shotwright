import AppKit
import SwiftUI

/// The floating HUD under the recorded region: format and cursor options plus Record
/// before starting, then the timer with Pause, Stop and Discard while recording.
/// Glimpse's own windows are excluded from the stream, so it never shows in the video.
final class RecordingBarPanel: NSPanel {
    @MainActor
    init(coordinator: RecordingCoordinator) {
        let host = NSHostingView(rootView: RecordingBarView(coordinator: coordinator))
        host.frame.size = host.fittingSize
        super.init(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = host
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // Key so Return and Esc work before recording starts.
    override var canBecomeKey: Bool { true }
}

struct RecordingBarView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    @AppStorage(RecordingSettings.formatKey) private var format = RecordingFormat.mp4.rawValue
    @AppStorage(RecordingSettings.showCursorKey) private var showCursor = true

    var body: some View {
        HStack(spacing: 8) {
            switch coordinator.phase {
            case .recording, .finishing: recordingControls
            default: setupControls
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 300, height: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.08, opacity: 0.88)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .padding(16) // room for the shadow
    }

    @ViewBuilder
    private var setupControls: some View {
        BarIconButton(symbol: "xmark", label: "Cancel (Esc)") { coordinator.cancel() }
        Picker("Format", selection: $format) {
            ForEach(RecordingFormat.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 96)
        BarIconButton(symbol: "cursorarrow", label: showCursor ? "Cursor shown" : "Cursor hidden", isOn: showCursor) {
            showCursor.toggle()
        }
        Spacer(minLength: 0)
        Button { coordinator.start() } label: {
            HStack(spacing: 6) {
                Circle().fill(.white).frame(width: 8, height: 8)
                Text("Record").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color(red: 0.93, green: 0.23, blue: 0.21)))
        }
        .buttonStyle(.plain)
        .disabled(coordinator.phase != .ready)
        .help("Start recording (Return)")
    }

    @ViewBuilder
    private var recordingControls: some View {
        Circle()
            .fill(Color(red: 0.93, green: 0.23, blue: 0.21))
            .frame(width: 10, height: 10)
            .opacity(coordinator.isPaused || Int(coordinator.elapsed * 2) % 2 == 0 ? 1 : 0.35)
            .padding(.leading, 6)
        Text(Recording.timeText(coordinator.elapsed))
            .font(.system(size: 14, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
        if coordinator.isPaused {
            Text("Paused").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
        Spacer(minLength: 0)
        BarIconButton(symbol: coordinator.isPaused ? "play.fill" : "pause.fill", label: coordinator.isPaused ? "Resume" : "Pause") {
            coordinator.togglePause()
        }
        Button { coordinator.stop() } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 9, height: 9)
                Text("Stop").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color(white: 0.11))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
        .help("Stop recording (⌥⇧7)")
        BarIconButton(symbol: "trash", label: "Discard recording") { coordinator.discard() }
    }
}

private struct BarIconButton: View {
    let symbol: String
    let label: String
    var isOn = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : .white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(isHovered || isOn ? 0.16 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A dashed outline around the area being recorded. Click-through, and left out of the video.
final class RecordingBorderWindow: NSWindow {
    private static let outset: CGFloat = 3

    @MainActor
    init(frame region: CGRect) {
        let frame = region.insetBy(dx: -Self.outset, dy: -Self.outset)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BorderView(frame: NSRect(origin: .zero, size: frame.size))
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
            let shadow = NSBezierPath(rect: rect)
            shadow.lineWidth = 3
            NSColor.black.withAlphaComponent(0.35).setStroke()
            shadow.stroke()
            let dashes = NSBezierPath(rect: rect)
            dashes.lineWidth = 1.5
            dashes.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.white.setStroke()
            dashes.stroke()
        }
    }
}
