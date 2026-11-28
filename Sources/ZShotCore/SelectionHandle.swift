import CoreGraphics

/// One of the eight grab points on a Selection: its corners and the middle of each side. AppKit's y grows upward, so top is maxY.
public enum SelectionHandle: CaseIterable, Equatable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    /// The edge it moves on each axis: -1 the min edge, 1 the max edge, 0 neither.
    private var sides: (x: Int, y: Int) {
        switch self {
        case .topLeft: return (-1, 1)
        case .top: return (0, 1)
        case .topRight: return (1, 1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        case .bottomLeft: return (-1, -1)
        case .bottom: return (0, -1)
        case .bottomRight: return (1, -1)
        }
    }

    public var isCorner: Bool { sides.x != 0 && sides.y != 0 }

    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: Self.pick(sides.x, rect.minX, rect.midX, rect.maxX),
            y: Self.pick(sides.y, rect.minY, rect.midY, rect.maxY))
    }

    /// A middle handle needs its side at least three radii long, so it never crowds the corners.
    public func isAvailable(on rect: CGRect, radius: CGFloat) -> Bool {
        if sides.x == 0 { return rect.width >= 3 * radius }
        if sides.y == 0 { return rect.height >= 3 * radius }
        return true
    }

    /// The handle within `radius` of `point`. Corners win over middle handles, then the nearer one.
    public static func hit(_ point: CGPoint, in rect: CGRect, radius: CGFloat) -> SelectionHandle? {
        func distanceSquared(_ handle: SelectionHandle) -> CGFloat {
            let center = handle.point(in: rect)
            let dx = point.x - center.x
            let dy = point.y - center.y
            return dx * dx + dy * dy
        }
        func rank(_ handle: SelectionHandle) -> (Int, CGFloat) {
            (handle.isCorner ? 0 : 1, distanceSquared(handle))
        }
        return allCases
            .filter { $0.isAvailable(on: rect, radius: radius) && distanceSquared($0) <= radius * radius }
            .min { rank($0) < rank($1) }
    }

    /// `rect` with this handle's edges moved to `point`. Dragging past the opposite edge flips it, and it keeps at least 1 pt a side.
    public func resized(_ rect: CGRect, to point: CGPoint) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if sides.x < 0 { minX = point.x } else if sides.x > 0 { maxX = point.x }
        if sides.y < 0 { minY = point.y } else if sides.y > 0 { maxY = point.y }
        let flipped = Geometry.rect(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
        return CGRect(x: flipped.minX, y: flipped.minY, width: max(flipped.width, 1), height: max(flipped.height, 1))
    }

    private static func pick(_ side: Int, _ low: CGFloat, _ mid: CGFloat, _ high: CGFloat) -> CGFloat {
        side < 0 ? low : side > 0 ? high : mid
    }
}
