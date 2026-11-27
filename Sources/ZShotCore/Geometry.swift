import CoreGraphics
import Foundation

public enum Geometry {
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static let compass: [CGPoint] = {
        let d = CGFloat(0.5).squareRoot()
        return [
            CGPoint(x: 1, y: 0), CGPoint(x: d, y: d), CGPoint(x: 0, y: 1), CGPoint(x: -d, y: d),
            CGPoint(x: -1, y: 0), CGPoint(x: -d, y: -d), CGPoint(x: 0, y: -1), CGPoint(x: d, y: -d),
        ]
    }()

    /// Moves `end` to the nearest 45 degree direction from `start`, keeping the length.
    public static func snapped45(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return end }
        let steps = Int((atan2(Double(dy), Double(dx)) / (Double.pi / 4)).rounded())
        let unit = compass[(steps + 8) % 8]
        return CGPoint(x: start.x + unit.x * length, y: start.y + unit.y * length)
    }

    /// Moves `end` so the box from `start` is a square of the larger side, keeping the drag direction.
    public static func squared(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }
}
