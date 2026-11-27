import CoreGraphics
import Foundation

public enum AnnotationRenderer {
    private static let arrowHalfAngle = 28.0 * Double.pi / 180

    /// Draws in the context's current user space, which callers set up as global points.
    public static func draw(_ annotations: [Annotation], in context: CGContext) {
        for annotation in annotations {
            draw(annotation, in: context)
        }
    }

    private static func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let color = annotation.swatch.cgColor
        let width = annotation.thickness.lineWidth
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case .line(let from, let to):
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        case .pen(let points):
            guard let first = points.first else { return }
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        case .rectangle(let rect):
            context.stroke(rect)
        case .ellipse(let rect):
            context.strokeEllipse(in: rect)
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, width: width, in: context)
        }
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, in context: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let ux = dx / length
        let uy = dy / length
        let headLength = min(length, max(12, 4.5 * width))
        let halfWidth = headLength * CGFloat(tan(arrowHalfAngle))
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)

        if headLength < length {
            context.move(to: from)
            context.addLine(to: base)
            context.strokePath()
        }
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth))
        context.addLine(to: CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth))
        context.closePath()
        context.fillPath()
    }
}
