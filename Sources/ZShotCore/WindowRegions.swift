import CoreGraphics

/// A window on screen, in global AppKit points.
public struct ScreenWindow: Equatable, Sendable {
    /// The CGWindowID.
    public let id: UInt32
    public let frame: CGRect
    /// Whether hovering it can choose it. Windows that are not targets, like the Dock and the menu bar, only cover others.
    public let isTarget: Bool

    public init(id: UInt32, frame: CGRect, isTarget: Bool) {
        self.id = id
        self.frame = frame
        self.isTarget = isTarget
    }
}

/// A window the user can choose, split into the part they can see and the part other windows cover.
public struct WindowTarget: Equatable, Sendable {
    /// The CGWindowID.
    public let id: UInt32
    /// Clipped to the displays.
    public let frame: CGRect
    /// `visible` and `covered` are disjoint and together tile `frame`.
    public let visible: [CGRect]
    public let covered: [CGRect]

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> WindowTarget {
        WindowTarget(
            id: id,
            frame: frame.offsetBy(dx: dx, dy: dy),
            visible: visible.map { $0.offsetBy(dx: dx, dy: dy) },
            covered: covered.map { $0.offsetBy(dx: dx, dy: dy) })
    }
}

public enum WindowRegions {
    /// `windows` run front to back. Every window covers the ones behind it, except a non-target window spanning
    /// a whole display: those are invisible full-screen overlays, and counting them would hide every window.
    /// Targets nobody can see are dropped.
    public static func targets(_ windows: [ScreenWindow], displays: [CGRect]) -> [WindowTarget] {
        let bounds = displays.reduce(CGRect.null) { $0.union($1) }
        var occluders: [CGRect] = []
        var targets: [WindowTarget] = []
        for window in windows {
            let frame = window.frame.intersection(bounds)
            guard !frame.isEmpty else { continue }
            if window.isTarget {
                let visible = occluders.reduce([frame]) { pieces, occluder in pieces.flatMap { subtract(occluder, from: $0) } }
                if !visible.isEmpty {
                    let covered = visible.reduce([frame]) { pieces, shown in pieces.flatMap { subtract(shown, from: $0) } }
                    targets.append(WindowTarget(id: window.id, frame: frame, visible: visible, covered: covered))
                }
            }
            if window.isTarget || !displays.contains(where: { frame.contains($0) }) {
                occluders.append(frame)
            }
        }
        return targets
    }

    /// `rect` minus `cut`, as up to four disjoint rects: full-width bands above and below the cut, and bands left and right of it.
    public static func subtract(_ cut: CGRect, from rect: CGRect) -> [CGRect] {
        let hole = rect.intersection(cut)
        guard !hole.isEmpty else { return [rect] }
        let pieces = [
            CGRect(x: rect.minX, y: hole.maxY, width: rect.width, height: rect.maxY - hole.maxY),
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: hole.minY - rect.minY),
            CGRect(x: rect.minX, y: hole.minY, width: hole.minX - rect.minX, height: hole.height),
            CGRect(x: hole.maxX, y: hole.minY, width: rect.maxX - hole.maxX, height: hole.height),
        ]
        return pieces.filter { !$0.isEmpty }
    }
}
