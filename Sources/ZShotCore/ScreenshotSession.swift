import CoreGraphics

public enum Phase: Equatable, Sendable {
    /// Crosshair; `hover` is the window under the mouse.
    case choosing(hover: CGRect?)
    /// Mouse is down but has not moved past the drag threshold yet.
    case pressing(origin: CGPoint, hover: CGRect?)
    case selecting(anchor: CGPoint, current: CGPoint)
    case annotating(selection: CGRect, draft: Draft?)
}

public enum Command: Equatable, Sendable {
    case cancel, undo, redo, finish, fullDisplay
    case selectTool(Tool)
    case selectSwatch(Swatch)
    case selectThickness(Thickness)
}

public enum Input: Equatable, Sendable {
    case mouseMoved(CGPoint)
    case mouseDown(CGPoint)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case shiftChanged(Bool)
    case command(Command)
}

public enum Outcome: Equatable, Sendable {
    case cancel
    case finish(selection: CGRect, annotations: [Annotation])
}

/// Screenshot mode state. All points and rects are global AppKit points.
public struct ScreenshotSession: Sendable {
    public static let dragThreshold: CGFloat = 4

    public let displays: [CGRect]
    /// Front to back, clipped to the displays.
    public private(set) var windows: [CGRect] = []
    public private(set) var phase: Phase = .choosing(hover: nil)
    public var style: ToolStyle
    public private(set) var history = AnnotationHistory()
    public private(set) var mouse: CGPoint
    public private(set) var shiftDown = false

    public init(displays: [CGRect], windows: [CGRect], style: ToolStyle, mouse: CGPoint) {
        self.displays = displays
        self.style = style
        self.mouse = mouse
        setWindows(windows)
    }

    /// History plus the Annotation being drawn, as it should appear right now.
    public var annotations: [Annotation] {
        guard case .annotating(_, let draft?) = phase else { return history.annotations }
        return history.annotations + [draft.annotation(constrained: shiftDown)]
    }

    public mutating func setWindows(_ windows: [CGRect]) {
        let bounds = displays.reduce(CGRect.null) { $0.union($1) }
        self.windows = windows.map { $0.intersection(bounds) }.filter { !$0.isEmpty }
        if case .choosing = phase {
            phase = .choosing(hover: window(at: mouse))
        }
    }

    public mutating func handle(_ input: Input) -> Outcome? {
        switch input {
        case .mouseMoved(let point):
            mouse = point
            if case .choosing = phase {
                phase = .choosing(hover: window(at: point))
            }
        case .mouseDown(let point):
            mouse = point
            mouseDown(at: point)
        case .mouseDragged(let point):
            mouse = point
            mouseDragged(to: point)
        case .mouseUp(let point):
            mouse = point
            mouseUp(at: point)
        case .shiftChanged(let down):
            shiftDown = down
        case .command(let command):
            return handle(command)
        }
        return nil
    }

    private mutating func mouseDown(at point: CGPoint) {
        switch phase {
        case .choosing:
            phase = .pressing(origin: point, hover: window(at: point))
        case .annotating(let selection, _):
            phase = .annotating(selection: selection, draft: Draft(style: style, start: point))
        case .pressing, .selecting:
            break
        }
    }

    private mutating func mouseDragged(to point: CGPoint) {
        switch phase {
        case .pressing(let origin, _):
            if abs(point.x - origin.x) >= Self.dragThreshold || abs(point.y - origin.y) >= Self.dragThreshold {
                phase = .selecting(anchor: origin, current: point)
            }
        case .selecting(let anchor, _):
            phase = .selecting(anchor: anchor, current: point)
        case .annotating(let selection, var draft?):
            draft.extend(to: point)
            phase = .annotating(selection: selection, draft: draft)
        case .choosing, .annotating(_, .none):
            break
        }
    }

    private mutating func mouseUp(at point: CGPoint) {
        switch phase {
        case .pressing(_, let hover):
            if let hover {
                phase = .annotating(selection: hover, draft: nil)
            } else {
                phase = .choosing(hover: nil)
            }
        case .selecting(let anchor, _):
            let selection = Geometry.rect(from: anchor, to: point)
            if selection.width >= 1 && selection.height >= 1 {
                phase = .annotating(selection: selection, draft: nil)
            } else {
                phase = .choosing(hover: window(at: point))
            }
        case .annotating(let selection, var draft?):
            draft.extend(to: point)
            commit(draft)
            phase = .annotating(selection: selection, draft: nil)
        case .choosing, .annotating(_, .none):
            break
        }
    }

    private mutating func handle(_ command: Command) -> Outcome? {
        switch command {
        case .cancel:
            return .cancel
        case .undo:
            if !history.undo() { return .cancel }
        case .redo:
            history.redo()
        case .finish:
            guard case .annotating(let selection, let draft) = phase else { return nil }
            if let draft { commit(draft) }
            phase = .annotating(selection: selection, draft: nil)
            return .finish(selection: selection, annotations: history.annotations)
        case .fullDisplay:
            if let display = displays.first(where: { $0.contains(mouse) }) {
                phase = .annotating(selection: display, draft: nil)
            }
        case .selectTool(let tool):
            style.tool = tool
        case .selectSwatch(let swatch):
            style.swatch = swatch
        case .selectThickness(let thickness):
            style.thickness = thickness
        }
        return nil
    }

    private mutating func commit(_ draft: Draft) {
        let annotation = draft.annotation(constrained: shiftDown)
        if !annotation.shape.isDegenerate {
            history.add(annotation)
        }
    }

    private func window(at point: CGPoint) -> CGRect? {
        windows.first { $0.contains(point) }
    }
}
