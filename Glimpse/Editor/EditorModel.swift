import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class EditorModel: ObservableObject {
    struct Snapshot {
        var image: CGImage
        var annotations: [Annotation]
    }

    static let palette: [(name: String, color: Color)] = [
        ("Red", Color(red: 0.90, green: 0.22, blue: 0.23)),
        ("Orange", Color(red: 0.95, green: 0.56, blue: 0.00)),
        ("Yellow", Color(red: 0.96, green: 0.77, blue: 0.09)),
        ("Green", Color(red: 0.17, green: 0.66, blue: 0.29)),
        ("Blue", Color(red: 0.04, green: 0.39, blue: 0.85)),
        ("Black", Color(red: 0.11, green: 0.11, blue: 0.12)),
    ]

    let capture: Capture
    let scale: CGFloat

    @Published private(set) var image: CGImage
    @Published private(set) var pixelated: CGImage?
    @Published private(set) var annotations: [Annotation] = []
    @Published var tool: Tool = .arrow { didSet { if tool != .select { selectedID = nil } } }
    @Published var color: Color
    @Published var lineWidth: CGFloat = 4

    /// The annotation being drawn right now, not yet committed.
    @Published private(set) var draft: Annotation?
    @Published private(set) var cropRect: CGRect?
    @Published var selectedID: UUID?
    @Published var editingText: Annotation?
    @Published var zoom: CGFloat = 1

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var dragOrigin: [Annotation]?

    init(capture: Capture) {
        self.capture = capture
        self.scale = capture.scale
        self.image = capture.image
        self.color = Self.palette[0].color
        self.pixelated = Self.makePixelated(capture.image, scale: capture.scale)
    }

    var canvasSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Gestures (locations are in image points)

    func dragChanged(start: CGPoint, location: CGPoint) {
        commitText()
        switch tool {
        case .select:
            if dragOrigin == nil {
                selectedID = annotations.last { $0.bounds.contains(start) }?.id
                dragOrigin = annotations
            }
            guard let selectedID, let origin = dragOrigin,
                  let index = origin.firstIndex(where: { $0.id == selectedID }) else { return }
            annotations[index] = origin[index].offsetBy(CGSize(width: location.x - start.x, height: location.y - start.y))

        case .crop:
            cropRect = CGRect(x: min(start.x, location.x), y: min(start.y, location.y),
                              width: abs(location.x - start.x), height: abs(location.y - start.y))
                .intersection(CGRect(origin: .zero, size: canvasSize))

        case .text, .counter:
            break

        default:
            if draft == nil {
                draft = Annotation(tool: tool, start: start, end: start, points: tool.isFreehand ? [start] : [], color: color, lineWidth: lineWidth)
            }
            draft?.end = location
            if tool.isFreehand { draft?.points.append(location) }
        }
    }

    func dragEnded(start: CGPoint, location: CGPoint) {
        switch tool {
        case .select:
            if let origin = dragOrigin, origin != annotations {
                pushUndo(Snapshot(image: image, annotations: origin))
            }
            if dragOrigin == nil { selectedID = annotations.last { $0.bounds.contains(location) }?.id }
            dragOrigin = nil

        case .crop:
            break

        case .text:
            commitText()
            editingText = Annotation(tool: .text, start: location, end: location, color: color, lineWidth: lineWidth)

        case .counter:
            let next = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
            commit(Annotation(tool: .counter, start: location, end: location, color: color, lineWidth: lineWidth, number: next))

        default:
            defer { draft = nil }
            guard var annotation = draft else { return }
            annotation.end = location
            let distance = hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y)
            if distance > 3 || annotation.points.count > 3 { commit(annotation) }
        }
    }

    // MARK: Editing

    func commitText() {
        guard let text = editingText else { return }
        editingText = nil
        if !text.text.trimmingCharacters(in: .whitespaces).isEmpty { commit(text) }
    }

    func deleteSelection() {
        guard let selectedID else { return }
        pushUndo(currentSnapshot)
        annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    func applyCrop() {
        guard let cropRect, cropRect.width >= 4, cropRect.height >= 4 else { return }
        let pixelRect = CGRect(x: cropRect.minX * scale, y: cropRect.minY * scale,
                               width: cropRect.width * scale, height: cropRect.height * scale).integral
        guard let cropped = image.cropping(to: pixelRect) else { return }
        pushUndo(currentSnapshot)
        let offset = CGSize(width: -cropRect.minX, height: -cropRect.minY)
        annotations = annotations.map { $0.offsetBy(offset) }
        setImage(cropped)
        self.cropRect = nil
        tool = .arrow
    }

    func cancelCrop() {
        cropRect = nil
    }

    func undo() {
        commitText()
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    // MARK: Output

    /// The screenshot with every annotation burned in, at full resolution.
    func renderedImage() -> CGImage? {
        commitText()
        let size = canvasSize
        let image = image, pixelated = pixelated, annotations = annotations, scale = scale
        let renderer = ImageRenderer(content:
            Canvas { context, _ in
                AnnotationRenderer.draw(in: &context, image: image, pixelated: pixelated, imageScale: scale, size: size, annotations: annotations)
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Writes the edits back to the capture so Quick Access, history and saving all see them.
    func applyToCapture() -> Bool {
        guard let rendered = renderedImage() else { return false }
        capture.image = rendered
        return true
    }

    // MARK: Private

    private var currentSnapshot: Snapshot { Snapshot(image: image, annotations: annotations) }

    private func commit(_ annotation: Annotation) {
        pushUndo(currentSnapshot)
        annotations.append(annotation)
    }

    private func pushUndo(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    private func restore(_ snapshot: Snapshot) {
        annotations = snapshot.annotations
        if snapshot.image !== image { setImage(snapshot.image) }
        selectedID = nil
    }

    private func setImage(_ newImage: CGImage) {
        image = newImage
        pixelated = Self.makePixelated(newImage, scale: scale)
    }

    private static func makePixelated(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(10 * scale)
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }
}
