import AppKit

/// Draws one screen's part of the capture overlay: the frozen screen, the dimmed
/// surround, the selection with handles and size badge, the loupe and the hint bar.
final class SelectionView: NSView {
    private let screen: NSScreen
    private unowned let controller: SelectionController
    private let frozenImage: NSImage?
    private let frozenCG: CGImage?
    private let scale: CGFloat

    private var dragStart: NSPoint?
    private var selection: NSRect?

    init(screen: NSScreen, controller: SelectionController, frozen: Capture?) {
        self.screen = screen
        self.controller = controller
        self.frozenCG = frozen?.image
        self.frozenImage = frozen.map { NSImage(cgImage: $0.image, size: screen.frame.size) }
        self.scale = frozen?.scale ?? screen.backingScaleFactor
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func cancelDrag() {
        dragStart = nil
        selection = nil
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if controller.mode == .window {
            controller.finishWindow()
            return
        }
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        selection = rect(from: dragStart, to: convert(event.locationInWindow, from: nil), flags: event.modifierFlags)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let selection = selection?.integral, selection.width >= 4, selection.height >= 4 else {
            if controller.clickSelectsScreen, controller.mode == .area {
                controller.finishArea(bounds, on: screen)
                return
            }
            self.selection = nil
            needsDisplay = true
            return
        }
        controller.finishArea(selection, on: screen)
    }

    /// ⇧ locks to a square, ⌥ grows the selection out from the start point.
    private func rect(from start: NSPoint, to end: NSPoint, flags: NSEvent.ModifierFlags) -> NSRect {
        var dx = end.x - start.x
        var dy = end.y - start.y
        if flags.contains(.shift) {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        let raw: NSRect
        if flags.contains(.option) {
            raw = NSRect(x: start.x - abs(dx), y: start.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        } else {
            raw = NSRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
        }
        return raw.intersection(bounds)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        frozenImage?.draw(in: bounds)

        let hole: NSRect? = controller.mode == .area ? selection : controller.hoveredWindowRect(in: screen)

        let dim = NSBezierPath(rect: bounds)
        if let hole {
            dim.append(NSBezierPath(rect: hole))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        if let hole {
            if controller.mode == .window {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                hole.fill()
                NSColor.controlAccentColor.setStroke()
                let border = NSBezierPath(rect: hole.insetBy(dx: 1.5, dy: 1.5))
                border.lineWidth = 3
                border.stroke()
            } else {
                NSColor.white.setStroke()
                let border = NSBezierPath(rect: hole.insetBy(dx: 0.5, dy: 0.5))
                border.lineWidth = 1
                border.stroke()
                drawHandles(around: hole)
            }
            drawSizeBadge(for: hole)
        }

        let mouse = localMouse
        if controller.mode == .area, bounds.contains(mouse) {
            drawLoupe(at: mouse)
        }
        if NSScreen.underMouse == screen {
            drawHintBar()
        }
    }

    private var localMouse: NSPoint {
        let global = controller.mouseLocation
        return NSPoint(x: global.x - screen.frame.minX, y: global.y - screen.frame.minY)
    }

    private func drawHandles(around rect: NSRect) {
        let points = [
            NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.midX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.midY), NSPoint(x: rect.maxX, y: rect.midY),
            NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.midX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY),
        ]
        for point in points {
            let handle = NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: handle.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    private func drawSizeBadge(for rect: NSRect) {
        let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var badge = NSRect(x: rect.minX, y: rect.minY - size.height - 16, width: size.width + 18, height: size.height + 8)
        if badge.minY < 8 { badge.origin.y = rect.minY + 8 } // keep it on screen
        NSColor(white: 0.08, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: NSPoint(x: badge.minX + 9, y: badge.minY + 4), withAttributes: attributes)
    }

    private func drawLoupe(at point: NSPoint) {
        guard let frozenCG, let context = NSGraphicsContext.current?.cgContext else { return }
        let diameter: CGFloat = 128
        let zoom: CGFloat = 8
        // Place the loupe below-right of the cursor, flipping when near an edge.
        var origin = NSPoint(x: point.x + 24, y: point.y - 24 - diameter)
        if origin.x + diameter > bounds.maxX { origin.x = point.x - 24 - diameter }
        if origin.y < bounds.minY { origin.y = point.y + 24 }
        let frame = NSRect(origin: origin, size: NSSize(width: diameter, height: diameter))

        // Source pixels around the cursor (CGImage space has a top-left origin).
        let side = diameter / zoom * scale
        let source = CGRect(x: point.x * scale - side / 2, y: (bounds.height - point.y) * scale - side / 2, width: side, height: side)

        context.saveGState()
        NSBezierPath(ovalIn: frame).addClip()
        NSColor.black.setFill()
        frame.fill()
        if let crop = frozenCG.cropping(to: source) {
            context.interpolationQuality = .none
            context.draw(crop, in: frame)
        }
        // Center pixel guides.
        NSColor.controlAccentColor.withAlphaComponent(0.6).setFill()
        NSRect(x: frame.midX - zoom / 2, y: frame.minY, width: zoom, height: frame.height).fill()
        NSRect(x: frame.minX, y: frame.midY - zoom / 2, width: frame.width, height: zoom).fill()

        let label = "x \(Int(point.x)) · y \(Int(bounds.height - point.y))"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white]
        let labelRect = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 18)
        NSColor(white: 0.08, alpha: 0.8).setFill()
        labelRect.fill()
        let labelSize = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: labelRect.midX - labelSize.width / 2, y: labelRect.minY + 3), withAttributes: attributes)
        context.restoreGState()

        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: frame.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3
        ring.stroke()
    }

    private func drawHintBar() {
        let items: [(String, String)] = controller.mode == .area
            ? controller.clickSelectsScreen
                ? [("Drag", "to record an area"), ("Click", "full screen"), ("Space", "window mode"), ("Esc", "cancel")]
                : [("Drag", "to select"), ("Space", "window mode"), ("⇧", "square"), ("⌥", "from center"), ("Esc", "cancel")]
            : [("Click", controller.clickSelectsScreen ? "to record window" : "to capture window"), ("Space", "area mode"), ("Esc", "cancel")]
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white]
        let regular: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white]
        let text = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "     ", attributes: regular)) }
            text.append(NSAttributedString(string: item.0 + " ", attributes: bold))
            text.append(NSAttributedString(string: item.1, attributes: regular))
        }
        let size = text.size()
        let bar = NSRect(x: bounds.midX - size.width / 2 - 16, y: 28, width: size.width + 32, height: size.height + 18)
        NSColor(white: 0.08, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
        text.draw(at: NSPoint(x: bar.minX + 16, y: bar.minY + 9))
    }
}
