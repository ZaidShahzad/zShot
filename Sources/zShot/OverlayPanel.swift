import AppKit
import ZShotCore

/// Screenshot mode's window on one display. Built at launch and kept ordered out until the Capture hotkey.
/// It never activates zShot, so the frontmost app keeps focus.
@MainActor
final class OverlayPanel: NSPanel {
    let displayScreen: NSScreen
    let screenFrame: CGRect
    var onInput: (@MainActor (Input) -> Void)?

    private let backdrop: BackdropView
    private let liftedView = LiftedView(frame: .zero)
    private let chrome: ChromeView
    private let canvas = CanvasView(frame: .zero)
    private let handles: HandlesView
    private let sizeLabel = NSTextField(labelWithString: "")
    private let toolStrip = Toolbar()
    private var mouseDownInToolbar = false
    /// The Selection as last rendered, in global points, so the pointer can turn into a resize pointer over its handles.
    private var renderedSelection: CGRect?
    /// The handle being dragged, as last rendered.
    private var draggedHandle: SelectionHandle?

    init(screen: NSScreen) {
        displayScreen = screen
        screenFrame = screen.frame
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        backdrop = BackdropView(frame: bounds)
        chrome = ChromeView(frame: bounds)
        handles = HandlesView(frame: bounds)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        sizeLabel.textColor = .white
        sizeLabel.alignment = .center
        sizeLabel.wantsLayer = true
        sizeLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        sizeLabel.layer?.cornerRadius = 6
        sizeLabel.layer?.borderWidth = 1
        sizeLabel.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        sizeLabel.isHidden = true

        chrome.autoresizingMask = [.width, .height]
        handles.autoresizingMask = [.width, .height]
        backdrop.addSubview(liftedView)
        backdrop.addSubview(chrome)
        backdrop.addSubview(canvas)
        backdrop.addSubview(handles)
        backdrop.addSubview(sizeLabel)
        backdrop.addSubview(toolStrip)
        contentView = backdrop
        initialFirstResponder = backdrop

        toolStrip.isHidden = true
        toolStrip.onCommand = { [weak self] command in
            self?.onInput?(.command(command))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setFrozenImage(_ image: CGImage?) {
        backdrop.image = image
    }

    /// Shows one window, captured by itself, over the frozen image and under the dim and the Annotations.
    /// Its frame may run past this display.
    func setLifted(_ lifted: LiftedWindow?) {
        guard let lifted else {
            liftedView.hide()
            return
        }
        let frame = lifted.image.frame
        liftedView.show(
            lifted.image.image,
            frame: frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY),
            visible: lifted.visible.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) })
    }

    func show() {
        orderFrontRegardless()
        _ = makeFirstResponder(backdrop)
    }

    /// `selectedWindow` is the window the Selection came from, outlined like a hovered window. Areas and displays get a square.
    func render(_ session: ScreenshotSession, selectedWindow: WindowTarget?, showsToolbar: Bool) {
        let origin = screenFrame.origin
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }

        var hole: ChromeView.Hole?
        var selection: CGRect?
        var selectingSize: CGSize?
        switch session.phase {
        case .choosing(let hover), .pressing(_, let hover):
            if let hover {
                hole = .window(hover.offsetBy(dx: -origin.x, dy: -origin.y))
            } else if session.displayUnderMouse == screenFrame {
                // Over the desktop a click takes the whole display, so the whole display lights up.
                hole = .area(backdrop.bounds)
            }
        case .selecting(let anchor, let current):
            let rect = Geometry.rect(from: anchor, to: current)
            hole = .area(local(rect))
            selectingSize = rect.size
        case .annotating(let rect, _):
            if let selectedWindow {
                hole = .window(selectedWindow.offsetBy(dx: -origin.x, dy: -origin.y))
            } else {
                hole = .area(local(rect))
            }
            selection = rect
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chrome.update(hole: hole)
        handles.update(selection: selection.map(local))
        CATransaction.commit()
        renderedSelection = selection
        draggedHandle = session.activeHandle

        if let selection {
            let frame = local(selection).intersection(backdrop.bounds)
            canvas.isHidden = frame.isNull
            if !frame.isNull {
                canvas.show(session.annotations, frame: frame, globalOrigin: CGPoint(x: frame.minX + origin.x, y: frame.minY + origin.y))
            }
        } else {
            canvas.isHidden = true
        }

        let readout: String?
        switch session.phase {
        case .choosing, .pressing:
            // Like macOS's own screenshot pointer: the position in points from the display's top-left corner.
            readout = "\(Int((session.mouse.x - origin.x).rounded(.down)))  \(Int((screenFrame.maxY - session.mouse.y).rounded(.down)))"
        case .selecting:
            let scale = displayScreen.backingScaleFactor
            readout = selectingSize.map { "\(Int(($0.width * scale).rounded())) \u{00D7} \(Int(($0.height * scale).rounded()))" }
        case .annotating:
            readout = nil
        }
        if let readout, screenFrame.contains(session.mouse) {
            sizeLabel.stringValue = readout
            sizeLabel.sizeToFit()
            sizeLabel.setFrameSize(NSSize(width: sizeLabel.frame.width + 12, height: sizeLabel.frame.height + 4))
            let mouse = CGPoint(x: session.mouse.x - origin.x, y: session.mouse.y - origin.y)
            var labelOrigin = CGPoint(x: mouse.x + 12, y: mouse.y - 12 - sizeLabel.frame.height)
            labelOrigin.x = min(labelOrigin.x, backdrop.bounds.maxX - sizeLabel.frame.width)
            labelOrigin.y = max(labelOrigin.y, 0)
            sizeLabel.setFrameOrigin(labelOrigin)
            sizeLabel.isHidden = false
        } else {
            sizeLabel.isHidden = true
        }

        if showsToolbar, let selection {
            toolStrip.update(style: session.style)
            toolStrip.setFrameOrigin(toolbarOrigin(for: local(selection)))
            toolStrip.isHidden = false
        } else {
            toolStrip.isHidden = true
        }
    }

    /// Below the Selection, right aligned; above it if there is no room; inside its bottom edge otherwise.
    private func toolbarOrigin(for selection: CGRect) -> CGPoint {
        let gap: CGFloat = 8
        let size = toolStrip.frame.size
        let bounds = backdrop.bounds
        var y = selection.minY - gap - size.height
        if y < bounds.minY {
            y = selection.maxY + gap
            if y + size.height > bounds.maxY {
                y = selection.minY + gap
            }
        }
        let x = min(max(selection.maxX - size.width, bounds.minX + gap), bounds.maxX - size.width - gap)
        return CGPoint(x: x, y: y)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if !isKeyWindow { makeKey() }
            mouseDownInToolbar = !toolStrip.isHidden && toolStrip.frame.contains(event.locationInWindow)
            if mouseDownInToolbar {
                super.sendEvent(event)
            } else {
                onInput?(.mouseDown(globalPoint(event)))
            }
        case .leftMouseDragged:
            if mouseDownInToolbar {
                super.sendEvent(event)
            } else {
                if let draggedHandle {
                    ResizeCursor.cursor(for: draggedHandle).set()
                }
                onInput?(.mouseDragged(globalPoint(event)))
            }
        case .leftMouseUp:
            if mouseDownInToolbar {
                super.sendEvent(event)
            } else {
                onInput?(.mouseUp(globalPoint(event)))
            }
            mouseDownInToolbar = false
        case .mouseMoved:
            if !isKeyWindow { makeKey() }
            let point = globalPoint(event)
            // Set on every move: zShot never activates, so cursor rects alone don't reliably hold.
            if !toolStrip.isHidden && toolStrip.frame.contains(event.locationInWindow) {
                NSCursor.arrow.set()
            } else if let selection = renderedSelection,
                      let handle = SelectionHandle.hit(point, in: selection, radius: ScreenshotSession.handleRadius) {
                ResizeCursor.cursor(for: handle).set()
            } else {
                ScreenshotCursor.shared.set()
            }
            onInput?(.mouseMoved(point))
        case .flagsChanged:
            onInput?(.shiftChanged(event.modifierFlags.contains(.shift)))
        case .keyDown:
            if !handleKey(event) {
                super.sendEvent(event)
            }
        default:
            super.sendEvent(event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKey(event)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard let command = Command.from(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            command: flags.contains(.command),
            shift: flags.contains(.shift))
        else { return false }
        onInput?(.command(command))
        return true
    }

    /// The content view is not flipped, so window coordinates convert straight to global AppKit points.
    private func globalPoint(_ event: NSEvent) -> CGPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

/// Holds the frozen display image as layer contents, so it is shown without redrawing.
private final class BackdropView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        layer?.contents = image
    }

    override func cursorUpdate(with event: NSEvent) {
        ScreenshotCursor.shared.set()
    }
}

/// Holds a lifted window's image as layer contents, stretched to the view and masked to its visible part.
private final class LiftedView: NSView {
    private let imageLayer = CALayer()
    private let visibleMask = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        imageLayer.mask = visibleMask
        layer?.addSublayer(imageLayer)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `frame` is in the superview's coordinates and `visible` in this view's. Fades in when it was hidden.
    func show(_ image: CGImage, frame: CGRect, visible: [CGRect]) {
        self.frame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        visibleMask.frame = bounds
        imageLayer.contents = image
        let path = CGMutablePath()
        path.addRects(visible)
        visibleMask.path = path
        CATransaction.commit()

        guard isHidden else { return }
        isHidden = false
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.07
        layer?.add(fade, forKey: "opacity")
    }

    func hide() {
        isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        CATransaction.commit()
    }
}

/// Dims everything outside the hole and borders it. The dim and the border share one hole path, so they move together.
/// A window hole also stays dimmed, and unbordered, where other windows cover it.
private final class ChromeView: NSView {
    enum Hole: Equatable {
        /// The hovered or selected window: rounded like a window, outlined in white, cross-fades to the next window.
        case window(WindowTarget)
        /// An area being dragged out, or a dragged or full-display Selection: square, bordered in white, follows the mouse exactly.
        case area(CGRect)
    }

    private static let windowCornerRadius: CGFloat = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) ? 16 : 10

    private let dim = CAShapeLayer()
    /// While dragging, the hole moves on every mouse event. Moving four solid layers costs nothing,
    /// unlike re-rasterizing a full-screen shape, so areas are dimmed with these instead of `dim`.
    private let areaDims: [CALayer] = (0..<4).map { _ in CALayer() }
    /// Dims the covered parts of a window hole. They are rects, so `coveredMask` trims them to the rounded outline;
    /// adding them to `dim`'s even-odd path instead would brighten the window's rounded corners.
    private let coveredDim = CAShapeLayer()
    private let coveredMask = CAShapeLayer()
    private let border = CAShapeLayer()
    /// Keeps a window's border to its visible parts.
    private let borderMask = CAShapeLayer()
    /// A soft drop shadow around the highlighted window, like a raised window. `shadowMask` keeps it on what lies behind the window.
    private let windowShadow = CAShapeLayer()
    private let shadowMask = CAShapeLayer()
    private var hole: Hole?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let dimColor = NSColor.black.withAlphaComponent(0.5).cgColor
        dim.fillColor = dimColor
        dim.fillRule = .evenOdd
        dim.path = CGPath(rect: bounds, transform: nil)
        coveredDim.fillColor = dimColor
        border.fillColor = nil
        windowShadow.fillColor = NSColor.black.cgColor
        windowShadow.shadowColor = NSColor.black.cgColor
        windowShadow.shadowOpacity = 0.55
        windowShadow.shadowRadius = 14
        windowShadow.shadowOffset = CGSize(width: 0, height: -6)
        windowShadow.isHidden = true
        windowShadow.mask = shadowMask
        layOutShapes()
        layer?.addSublayer(dim)
        for areaDim in areaDims {
            areaDim.backgroundColor = dimColor
            areaDim.isHidden = true
            layer?.addSublayer(areaDim)
        }
        layer?.addSublayer(windowShadow)
        layer?.addSublayer(coveredDim)
        layer?.addSublayer(border)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layOutShapes()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        for shape in shapes {
            shape.contentsScale = scale
        }
    }

    /// Every path and mask is in the view's coordinates, so each shape layer fills the view.
    private var shapes: [CAShapeLayer] { [dim, coveredDim, coveredMask, border, borderMask, windowShadow, shadowMask] }

    private func layOutShapes() {
        for shape in shapes {
            shape.frame = bounds
        }
    }

    func update(hole newHole: Hole?) {
        guard newHole != hole else { return }
        let previous = hole
        hole = newHole

        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        // Borders sit inside the hole. Outside it, a hole touching a display edge would draw a line on the next display.
        var borderPath: CGPath?
        var coveredPath: CGPath?
        var shadowPath: CGPath?
        var area: CGRect?
        switch newHole {
        case .window(let target):
            let width: CGFloat = 1.5
            let rect = target.frame
            let outline = Self.roundedRect(rect, radius: Self.windowCornerRadius)
            dimPath.addPath(outline)
            shadowPath = outline
            // Only the display the window is on draws its outline, so its edge never shows on a neighboring display.
            if !rect.intersection(bounds).isEmpty {
                borderPath = Self.roundedRect(rect.insetBy(dx: width / 2, dy: width / 2), radius: Self.windowCornerRadius - width / 2)
            }
            border.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
            border.lineWidth = width
            if !target.covered.isEmpty {
                let covered = CGMutablePath()
                covered.addRects(target.covered)
                coveredPath = covered
                coveredMask.path = outline
                let visible = CGMutablePath()
                visible.addRects(target.visible)
                borderMask.path = visible
            }
        case .area(let rect):
            let width: CGFloat = 1
            area = rect
            borderPath = CGPath(rect: rect.insetBy(dx: width / 2, dy: width / 2), transform: nil)
            border.strokeColor = NSColor.white.cgColor
            border.lineWidth = width
        case nil:
            break
        }

        if let area {
            layOutAreaDims(around: area)
        } else {
            dim.path = dimPath
        }
        dim.isHidden = area != nil
        for areaDim in areaDims {
            areaDim.isHidden = area == nil
        }
        // Masks only while part of the window is covered, so the usual unobstructed window costs no masking pass.
        coveredDim.path = coveredPath
        coveredDim.mask = coveredPath == nil ? nil : coveredMask
        border.mask = coveredPath == nil ? nil : borderMask
        border.path = borderPath
        windowShadow.isHidden = shadowPath == nil
        windowShadow.path = shadowPath
        windowShadow.shadowPath = shadowPath
        if case .window(let target) = newHole {
            // A shadow only falls on what is behind the window: never on the window itself,
            // on windows in front of it, or on the Dock and menu bar.
            let reach = WindowRegions.shadowReach
            let outside = CGMutablePath()
            outside.addRects(WindowRegions.subtract(
                [target.frame] + target.inFront, from: bounds.insetBy(dx: -reach, dy: -reach)))
            shadowMask.path = outside
        }

        switch (previous, newHole) {
        case (.some(.window(_)), .some(.window(_))):
            // Only the dimming fades. The old outline and shadow vanish at once, so nothing lingers on the last window.
            border.removeAllAnimations()
            windowShadow.removeAllAnimations()
            Self.crossFade(dim)
            Self.crossFade(coveredDim)
        case (_, .some(.window(_))):
            dim.removeAllAnimations()
            coveredDim.removeAllAnimations()
            border.removeAllAnimations()
            windowShadow.removeAllAnimations()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.04
            border.add(fade, forKey: "opacity")
            windowShadow.add(fade, forKey: "opacity")
        default:
            dim.removeAllAnimations()
            coveredDim.removeAllAnimations()
            border.removeAllAnimations()
            windowShadow.removeAllAnimations()
        }
    }

    private func layOutAreaDims(around rect: CGRect) {
        let b = bounds
        let h = rect.intersection(b)
        guard !h.isNull else {
            areaDims[0].frame = b
            for areaDim in areaDims.dropFirst() { areaDim.frame = .zero }
            return
        }
        areaDims[0].frame = CGRect(x: b.minX, y: h.maxY, width: b.width, height: b.maxY - h.maxY)
        areaDims[1].frame = CGRect(x: b.minX, y: b.minY, width: b.width, height: h.minY - b.minY)
        areaDims[2].frame = CGRect(x: b.minX, y: h.minY, width: h.minX - b.minX, height: h.height)
        areaDims[3].frame = CGRect(x: h.maxX, y: h.minY, width: b.maxX - h.maxX, height: h.height)
    }

    /// Fades from what is on screen now to the new window, so a fast sweep stays smooth. Purely visual: input never waits.
    private static func crossFade(_ layer: CALayer) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.05
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(transition, forKey: kCATransition)
    }

    /// CGPath traps on a corner radius over half the shorter side.
    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let clamped = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
    }
}

/// Draws Annotations, sized to the part of the Selection on this display so it clips them for free.
private final class CanvasView: NSView {
    private var annotations: [Annotation] = []
    private var globalOrigin: CGPoint = .zero

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ annotations: [Annotation], frame: CGRect, globalOrigin: CGPoint) {
        isHidden = false
        if self.frame != frame {
            self.frame = frame
            needsDisplay = true
        }
        if self.annotations != annotations || self.globalOrigin != globalOrigin {
            self.annotations = annotations
            self.globalOrigin = globalOrigin
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.translateBy(x: -globalOrigin.x, y: -globalOrigin.y)
        AnnotationRenderer.draw(annotations, in: context)
    }
}

/// The Selection's eight resize handles. Each display draws the part of each handle that falls on it.
private final class HandlesView: NSView {
    private static let diameter: CGFloat = 9
    private let dots: [CALayer] = SelectionHandle.allCases.map { _ in CALayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let size = Self.diameter
        for dot in dots {
            dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            dot.cornerRadius = size / 2
            dot.backgroundColor = NSColor.white.cgColor
            dot.borderWidth = 1
            dot.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
            dot.shadowColor = NSColor.black.cgColor
            dot.shadowOpacity = 0.3
            dot.shadowRadius = 1.5
            dot.shadowOffset = CGSize(width: 0, height: -0.5)
            dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
            dot.isHidden = true
            layer?.addSublayer(dot)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `selection` is in this view's coordinates; nil hides every handle. Call inside a transaction with actions disabled.
    func update(selection: CGRect?) {
        for (handle, dot) in zip(SelectionHandle.allCases, dots) {
            guard let selection, handle.isAvailable(on: selection, radius: ScreenshotSession.handleRadius) else {
                dot.isHidden = true
                continue
            }
            dot.position = handle.point(in: selection)
            dot.isHidden = !dot.frame.intersects(bounds)
        }
    }
}

/// The pointer over a resize handle: macOS's own frame resize pointers on macOS 15 and later, the plain resize pointers before.
@MainActor
enum ResizeCursor {
    static func cursor(for handle: SelectionHandle) -> NSCursor {
        if #available(macOS 15, *) {
            switch handle {
            case .topLeft: return .frameResize(position: .topLeft, directions: .all)
            case .top: return .frameResize(position: .top, directions: .all)
            case .topRight: return .frameResize(position: .topRight, directions: .all)
            case .left: return .frameResize(position: .left, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            }
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
        }
    }
}

/// Screenshot mode's pointer: macOS's own screenshot crosshair, shape and size 1:1, recolored so the lines are solid white
/// with a thin dark edge. The original ships inside HIServices; if a future macOS moves it, zShot uses the standard crosshair.
@MainActor
enum ScreenshotCursor {
    static let shared: NSCursor = load() ?? .crosshair

    private static func load() -> NSCursor? {
        let folder = URL(fileURLWithPath: "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/screenshotselection")
        guard let original = NSImage(contentsOf: folder.appendingPathComponent("cursor.pdf")),
              let white = whitened(original, scale: 2)
        else { return nil }
        let info = NSDictionary(contentsOf: folder.appendingPathComponent("info.plist"))
        let hotX = (info?["hotx"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? original.size.width / 2
        let hotY = (info?["hoty"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? original.size.height / 2
        return NSCursor(image: white, hotSpot: NSPoint(x: hotX, y: hotY))
    }

    /// Paints the asset's lines solid white, keeping its exact shape, and adds a soft dark edge so it reads on light screens.
    private static func whitened(_ image: NSImage, scale: CGFloat) -> NSImage? {
        let width = Int((image.size.width * scale).rounded())
        let height = Int((image.size.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4)
        else { return nil }
        // Drawing through AppKit renders the PDF as vectors at full resolution.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            // The lines are dark gray at about 85% opacity. Make them solid, and white (premultiplied: color equals alpha).
            let alpha = UInt8(min(255, Int(pixels[offset + 3]) * 3 / 2))
            pixels[offset] = alpha
            pixels[offset + 1] = alpha
            pixels[offset + 2] = alpha
            pixels[offset + 3] = alpha
        }
        guard let lines = context.makeImage(),
              let edged = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        edged.setShadow(offset: .zero, blur: 1.5 * scale, color: NSColor.black.withAlphaComponent(0.9).cgColor)
        edged.draw(lines, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = edged.makeImage() else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }
}
