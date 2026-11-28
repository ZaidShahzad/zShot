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
    private let sizeLabel = NSTextField(labelWithString: "")
    private let toolStrip = Toolbar()
    private var mouseDownInToolbar = false

    init(screen: NSScreen) {
        displayScreen = screen
        screenFrame = screen.frame
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        backdrop = BackdropView(frame: bounds)
        chrome = ChromeView(frame: bounds)
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

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .white
        sizeLabel.drawsBackground = true
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        sizeLabel.isHidden = true

        chrome.autoresizingMask = [.width, .height]
        backdrop.addSubview(liftedView)
        backdrop.addSubview(chrome)
        backdrop.addSubview(canvas)
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
            if let hover { hole = .window(hover.offsetBy(dx: -origin.x, dy: -origin.y)) }
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
        CATransaction.commit()

        if let selection {
            let frame = local(selection).intersection(backdrop.bounds)
            canvas.isHidden = frame.isNull
            if !frame.isNull {
                canvas.show(session.annotations, frame: frame, globalOrigin: CGPoint(x: frame.minX + origin.x, y: frame.minY + origin.y))
            }
        } else {
            canvas.isHidden = true
        }

        if let size = selectingSize, screenFrame.contains(session.mouse) {
            let scale = displayScreen.backingScaleFactor
            sizeLabel.stringValue = " \(Int((size.width * scale).rounded())) \u{00D7} \(Int((size.height * scale).rounded())) "
            sizeLabel.sizeToFit()
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
            onInput?(.mouseMoved(globalPoint(event)))
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
        NSCursor.crosshair.set()
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
        /// The hovered or selected window: rounded like a window, outlined like macOS's own thin window border, cross-fades to the next window.
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
    /// A soft drop shadow around the highlighted window, like a raised window. `shadowMask` keeps it outside the window.
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
        shadowMask.fillRule = .evenOdd
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
            borderPath = Self.roundedRect(rect.insetBy(dx: width / 2, dy: width / 2), radius: Self.windowCornerRadius - width / 2)
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            border.strokeColor = (isDark ? NSColor.white.withAlphaComponent(0.3) : NSColor.black.withAlphaComponent(0.25)).cgColor
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
        if let shadowPath {
            let outside = CGMutablePath()
            outside.addRect(bounds.insetBy(dx: -40, dy: -40))
            outside.addPath(shadowPath)
            shadowMask.path = outside
        }

        switch (previous, newHole) {
        case (.some(.window(_)), .some(.window(_))):
            Self.crossFade(dim)
            Self.crossFade(coveredDim)
            Self.crossFade(windowShadow)
            Self.crossFade(border)
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
        transition.duration = 0.07
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
