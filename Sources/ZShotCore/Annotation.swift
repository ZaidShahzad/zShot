import CoreGraphics

public enum Tool: String, CaseIterable, Sendable {
    case arrow, line, pen, rectangle, circle
}

public enum Swatch: String, CaseIterable, Sendable {
    case red, yellow, green, blue, black, white

    public var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch self {
        case .red: return (1.0, 0.23, 0.19, 1)
        case .yellow: return (1.0, 0.8, 0.0, 1)
        case .green: return (0.2, 0.78, 0.35, 1)
        case .blue: return (0.0, 0.48, 1.0, 1)
        case .black: return (0, 0, 0, 1)
        case .white: return (1, 1, 1, 1)
        }
    }

    public var cgColor: CGColor {
        let c = rgba
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}

public enum Thickness: String, CaseIterable, Sendable {
    case thin, medium, thick

    public var lineWidth: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 4
        case .thick: return 8
        }
    }
}

public struct ToolStyle: Equatable, Sendable {
    public var tool: Tool
    public var swatch: Swatch
    public var thickness: Thickness

    public init(tool: Tool = .arrow, swatch: Swatch = .red, thickness: Thickness = .medium) {
        self.tool = tool
        self.swatch = swatch
        self.thickness = thickness
    }
}

public enum Shape: Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case pen([CGPoint])
    case rectangle(CGRect)
    case ellipse(CGRect)

    /// Pen strokes need every point, so for `.pen` this only covers the first segment.
    public static func make(tool: Tool, start: CGPoint, end: CGPoint, constrained: Bool) -> Shape {
        switch tool {
        case .arrow:
            return .arrow(from: start, to: constrained ? Geometry.snapped45(from: start, to: end) : end)
        case .line:
            return .line(from: start, to: constrained ? Geometry.snapped45(from: start, to: end) : end)
        case .pen:
            return .pen(start == end ? [start] : [start, end])
        case .rectangle:
            return .rectangle(Geometry.rect(from: start, to: constrained ? Geometry.squared(from: start, to: end) : end))
        case .circle:
            return .ellipse(Geometry.rect(from: start, to: constrained ? Geometry.squared(from: start, to: end) : end))
        }
    }

    public var isDegenerate: Bool {
        switch self {
        case .arrow(let from, let to), .line(let from, let to):
            return from == to
        case .pen(let points):
            return points.count < 2
        case .rectangle(let rect), .ellipse(let rect):
            return rect.width == 0 || rect.height == 0
        }
    }
}

public struct Annotation: Equatable, Sendable {
    public var shape: Shape
    public var swatch: Swatch
    public var thickness: Thickness

    public init(shape: Shape, swatch: Swatch, thickness: Thickness) {
        self.shape = shape
        self.swatch = swatch
        self.thickness = thickness
    }
}

/// An Annotation still being dragged out. Pen keeps every point; other tools keep the start and the latest point.
public struct Draft: Equatable, Sendable {
    public let style: ToolStyle
    public private(set) var points: [CGPoint]

    public init(style: ToolStyle, start: CGPoint) {
        self.style = style
        self.points = [start]
    }

    public mutating func extend(to point: CGPoint) {
        guard let last = points.last, last != point else { return }
        if style.tool == .pen {
            points.append(point)
        } else {
            points = [points[0], point]
        }
    }

    public func annotation(constrained: Bool) -> Annotation {
        let shape: Shape
        if style.tool == .pen {
            shape = .pen(points)
        } else {
            shape = Shape.make(tool: style.tool, start: points[0], end: points[points.count - 1], constrained: constrained)
        }
        return Annotation(shape: shape, swatch: style.swatch, thickness: style.thickness)
    }
}
