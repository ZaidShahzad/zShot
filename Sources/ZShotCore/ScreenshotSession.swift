import CoreGraphics

public enum Phase: Equatable, Sendable {
    /// Crosshair; `hover` is the window under the mouse.
    case choosing(hover: WindowTarget?)
    /// Mouse is down but has not moved past the drag threshold yet.
    case pressing(origin: CGPoint, hover: WindowTarget?)
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
    /// How close to a resize handle's center a press grabs it.
    public static let handleRadius: CGFloat = 8

    public let displays: [CGRect]
    /// Front to back.
    public private(set) var windows: [WindowTarget] = []
    public private(set) var phase: Phase = .choosing(hover: nil)
    /// The window a click chose, while it is still the Selection.
    public private(set) var selectedWindow: WindowTarget?
    public var style: ToolStyle
    public private(set) var history = AnnotationHistory()
    public private(set) var mouse: CGPoint
    public private(set) var shiftDown = false
    /// Where handles may sit: each display's usable part, without the menu bar or Dock. Empty means anywhere.
    public var handleArea: [CGRect] = []
    /// Set only while annotating with no draft: a press either grabs a handle or starts an Annotation.
    private var resize: Resize?

    /// A handle drag. It always resizes the Selection as it was at the press, so dragging past the opposite edge flips cleanly.
    private struct Resize: Sendable {
        let handle: SelectionHandle
        let start: CGRect
        /// From the press to the handle's center, so the edge does not jump to the pointer.
        let offset: CGPoint

        func selection(to point: CGPoint) -> CGRect {
            handle.resized(start, to: CGPoint(x: point.x + offset.x, y: point.y + offset.y))
        }
    }

    /// The handle being dragged, while the Selection is being resized.
    public var activeHandle: SelectionHandle? { resize?.handle }

    /// The rect whose handles show and can be grabbed: the Selection, or before there is one,
    /// the hovered window or the display under the pointer.
    public var handleTarget: CGRect? {
        switch phase {
        case .choosing(let hover), .pressing(_, let hover):
            return hover?.frame ?? displayUnderMouse
        case .selecting(let anchor, let current):
            return Geometry.rect(from: anchor, to: current)
        case .annotating(let selection, _):
            return selection
        }
    }

    /// The rect `rect`'s handles are laid out on. Kept inside the part of `handleArea` it touches, and pulled in from any edge
    /// at, near, or past that area's edge, so no handle hides under the menu bar or Dock or runs off the display.
    public func handleLayout(for rect: CGRect) -> CGRect {
        let touched = handleArea.filter { !$0.intersection(rect).isEmpty }
        guard let first = touched.first else { return rect }
        let area = touched.dropFirst().reduce(first) { $0.union($1) }
        let reach = Self.handleRadius
        let inset = reach + 1
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if minX < area.minX + reach { minX = area.minX + inset }
        if maxX > area.maxX - reach { maxX = area.maxX - inset }
        if minY < area.minY + reach { minY = area.minY + inset }
        if maxY > area.maxY - reach { maxY = area.maxY - inset }
        // A sliver along an edge collapses to its middle rather than turning inside out.
        if minX > maxX {
            minX = (minX + maxX) / 2
            maxX = minX
        }
        if minY > maxY {
            minY = (minY + maxY) / 2
            maxY = minY
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public init(displays: [CGRect], windows: [WindowTarget], style: ToolStyle, mouse: CGPoint) {
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

    /// The display a click selects when no window is under the pointer.
    public var displayUnderMouse: CGRect? { display(at: mouse) }

    public mutating func setWindows(_ windows: [WindowTarget]) {
        self.windows = windows
        if case .choosing = phase {
            phase = .choosing(hover: window(at: mouse))
        }
    }

    public mutating func handle(_ input: Input) -> Outcome? {
        switch input {
        case .mouseMoved(let point):
            let target = handleTarget
            mouse = point
            // A handle reaches past its window's edge, so the hover holds while the pointer is on one.
            if case .choosing = phase, grabbedHandle(at: point, on: target) == nil {
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
        case .choosing(let hover):
            // A press on a handle selects its rect, as a click would, and starts resizing it in the same press.
            if let target = handleTarget, let handle = grabbedHandle(at: point, on: target) {
                selectedWindow = hover
                phase = .annotating(selection: target, draft: nil)
                startResize(handle, on: target, at: point)
            } else {
                phase = .pressing(origin: point, hover: window(at: point))
            }
        case .annotating(let selection, _):
            if let handle = grabbedHandle(at: point, on: selection) {
                startResize(handle, on: selection, at: point)
            } else {
                phase = .annotating(selection: selection, draft: Draft(style: style, start: point))
            }
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
        case .annotating(let selection, .none):
            guard let resize else { break }
            let resized = resize.selection(to: point)
            // A resized window is a plain area: it no longer matches the window, so it is no longer outlined or lifted as one.
            if resized != selection {
                selectedWindow = nil
                phase = .annotating(selection: resized, draft: nil)
            }
        case .choosing:
            break
        }
    }

    private mutating func mouseUp(at point: CGPoint) {
        switch phase {
        case .pressing(_, let hover):
            selectedWindow = hover
            if let selection = hover?.frame ?? display(at: point) {
                phase = .annotating(selection: selection, draft: nil)
            } else {
                phase = .choosing(hover: nil)
            }
        case .selecting(let anchor, _):
            selectedWindow = nil
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
        case .annotating(_, .none):
            resize = nil
        case .choosing:
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
            if let display = displayUnderMouse {
                selectedWindow = nil
                resize = nil
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

    private func grabbedHandle(at point: CGPoint, on rect: CGRect?) -> SelectionHandle? {
        guard let rect else { return nil }
        return SelectionHandle.hit(point, in: handleLayout(for: rect), radius: Self.handleRadius)
    }

    /// The offset runs to the handle as drawn, which may sit inside an edge that is off screen or under the Dock.
    private mutating func startResize(_ handle: SelectionHandle, on selection: CGRect, at point: CGPoint) {
        let center = handle.point(in: handleLayout(for: selection))
        resize = Resize(handle: handle, start: selection, offset: CGPoint(x: center.x - point.x, y: center.y - point.y))
    }

    private mutating func commit(_ draft: Draft) {
        let annotation = draft.annotation(constrained: shiftDown)
        if !annotation.shape.isDegenerate {
            history.add(annotation)
        }
    }

    private func display(at point: CGPoint) -> CGRect? {
        displays.first { $0.contains(point) }
    }

    /// Only the visible part counts, so a point over the Dock or a window in front never hovers the window behind it.
    private func window(at point: CGPoint) -> WindowTarget? {
        windows.first { window in window.visible.contains { $0.contains(point) } }
    }
}
