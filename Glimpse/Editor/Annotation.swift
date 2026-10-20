import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case select, crop
    case arrow, rectangle, ellipse, line, pen, highlighter, text, counter, pixelate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .crop: "Crop"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .counter: "Counter"
        case .pixelate: "Pixelate"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .line: "line.diagonal"
        case .pen: "scribble"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .pixelate: "checkerboard.rectangle"
        }
    }

    /// Tools that create an annotation (as opposed to select and crop).
    static let drawing: [Tool] = [.arrow, .rectangle, .ellipse, .line, .pen, .highlighter, .text, .counter, .pixelate]
    var isFreehand: Bool { self == .pen || self == .highlighter }
}

/// One mark on the screenshot. Coordinates are in image points, origin top-left.
struct Annotation: Identifiable, Equatable {
    let id = UUID()
    var tool: Tool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var color: Color
    var lineWidth: CGFloat
    var text: String = ""
    var number: Int = 0

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    var fontSize: CGFloat { 12 + lineWidth * 3 }
    var counterRadius: CGFloat { 10 + lineWidth * 1.5 }

    /// Rough hit-test box, used by the Select tool.
    var bounds: CGRect {
        switch tool {
        case .pen, .highlighter:
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        case .text:
            let width = max(CGFloat(text.count), 1) * fontSize * 0.6
            return CGRect(x: start.x, y: start.y, width: width, height: fontSize * 1.3)
        case .counter:
            let r = counterRadius
            return CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)
        default:
            return rect.insetBy(dx: -max(lineWidth, 6), dy: -max(lineWidth, 6))
        }
    }

    func offsetBy(_ delta: CGSize) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
        copy.end = CGPoint(x: end.x + delta.width, y: end.y + delta.height)
        copy.points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        return copy
    }
}
