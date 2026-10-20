import SwiftUI

/// Draws a screenshot and its annotations. Shared by the live canvas and the export.
enum AnnotationRenderer {
    static func draw(
        in context: inout GraphicsContext,
        image: CGImage,
        pixelated: CGImage?,
        imageScale: CGFloat,
        size: CGSize,
        annotations: [Annotation]
    ) {
        let frame = CGRect(origin: .zero, size: size)
        context.draw(Image(decorative: image, scale: imageScale), in: frame)
        for annotation in annotations {
            draw(annotation, in: &context, pixelated: pixelated, imageScale: imageScale, frame: frame)
        }
    }

    static func draw(_ a: Annotation, in context: inout GraphicsContext, pixelated: CGImage?, imageScale: CGFloat, frame: CGRect) {
        let stroke = StrokeStyle(lineWidth: a.lineWidth, lineCap: .round, lineJoin: .round)
        switch a.tool {
        case .rectangle:
            context.stroke(Path(roundedRect: a.rect, cornerRadius: a.lineWidth), with: .color(a.color), style: stroke)

        case .ellipse:
            context.stroke(Path(ellipseIn: a.rect), with: .color(a.color), style: stroke)

        case .line:
            var path = Path()
            path.move(to: a.start)
            path.addLine(to: a.end)
            context.stroke(path, with: .color(a.color), style: stroke)

        case .arrow:
            drawArrow(a, in: &context)

        case .pen, .highlighter:
            guard a.points.count > 1 else { return }
            var path = Path()
            path.addLines(a.points)
            if a.tool == .highlighter {
                var layer = context
                layer.blendMode = .multiply
                layer.opacity = 0.4
                layer.stroke(path, with: .color(a.color), style: StrokeStyle(lineWidth: a.lineWidth * 5, lineCap: .square, lineJoin: .round))
            } else {
                context.stroke(path, with: .color(a.color), style: stroke)
            }

        case .text:
            guard !a.text.isEmpty else { return }
            let text = Text(a.text)
                .font(.system(size: a.fontSize, weight: .bold))
                .foregroundColor(a.color)
            context.draw(text, at: a.start, anchor: .topLeading)

        case .counter:
            let r = a.counterRadius
            let circle = CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: circle), with: .color(a.color))
            context.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: 2)
            let label = Text("\(a.number)")
                .font(.system(size: r * 1.05, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            context.draw(label, at: a.start, anchor: .center)

        case .pixelate:
            guard let pixelated else { return }
            context.drawLayer { layer in
                layer.clip(to: Path(a.rect))
                layer.draw(Image(decorative: pixelated, scale: imageScale), in: frame)
            }

        case .select, .crop:
            break
        }
    }

    private static func drawArrow(_ a: Annotation, in context: inout GraphicsContext) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let angle = atan2(dy, dx)
        let headLength = min(max(a.lineWidth * 4, 14), length * 0.6)
        let headAngle = CGFloat.pi / 7
        let left = CGPoint(x: a.end.x - headLength * cos(angle - headAngle), y: a.end.y - headLength * sin(angle - headAngle))
        let right = CGPoint(x: a.end.x - headLength * cos(angle + headAngle), y: a.end.y - headLength * sin(angle + headAngle))
        // Stop the shaft inside the head so the tip stays sharp.
        let shaftEnd = CGPoint(x: a.end.x - headLength * 0.7 * cos(angle), y: a.end.y - headLength * 0.7 * sin(angle))

        var shaft = Path()
        shaft.move(to: a.start)
        shaft.addLine(to: shaftEnd)
        context.stroke(shaft, with: .color(a.color), style: StrokeStyle(lineWidth: a.lineWidth, lineCap: .round))

        var head = Path()
        head.move(to: a.end)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(a.color))
        context.stroke(head, with: .color(a.color), style: StrokeStyle(lineWidth: max(a.lineWidth / 2, 1), lineJoin: .round))
    }
}
