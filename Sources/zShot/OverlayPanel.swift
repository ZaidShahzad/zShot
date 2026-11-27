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

    func show() {
        orderFrontRegardless()
        _ = makeFirstResponder(backdrop)
    }

    func render(_ session: ScreenshotSession, showsToolbar: Bool) {
        let origin = screenFrame.origin
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }

        var hole: ChromeView.Hole?
        var selection: CGRect?
        var selectingSize: CGSize?
        switch session.phase {
        case .choosing(let hover), .pressing(_, let hover):
            if let hover { hole = .window(local(hover)) }
        case .selecting(let anchor, let current):
            let rect = Geometry.rect(from: anchor, to: current)
            hole = .area(local(rect))
            selectingSize = rect.size
        case .annotating(let rect, _):
            hole = .area(local(rect))
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

/// Dims everything outside the hole and borders it. The dim and the border share one hole path, so they move together.
private final class ChromeView: NSView {
    enum Hole: Equatable {
        /// The hovered window: rounded like a window, bordered in the accent color, glides to the next window.
        case window(CGRect)
        /// An area being dragged out, or the Selection: square, bordered in white, follows the mouse exactly.
        case area(CGRect)
    }

    private static let windowCornerRadius: CGFloat = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) ? 16 : 10

    private let dim = CAShapeLayer()
    /// While dragging, the hole moves on every mouse event. Moving four solid layers costs nothing,
    /// unlike re-rasterizing a full-screen shape, so areas are dimmed with these instead of `dim`.
    private let areaDims: [CALayer] = (0..<4).map { _ in CALayer() }
    private let border = CAShapeLayer()
    private var hole: Hole?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let dimColor = NSColor.black.withAlphaComponent(0.4).cgColor
        dim.fillColor = dimColor
        dim.fillRule = .evenOdd
        dim.path = CGPath(rect: bounds, transform: nil)
        border.fillColor = nil
        layer?.addSublayer(dim)
        for areaDim in areaDims {
            areaDim.backgroundColor = dimColor
            areaDim.isHidden = true
            layer?.addSublayer(areaDim)
        }
        layer?.addSublayer(border)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        dim.contentsScale = scale
        border.contentsScale = scale
    }

    func update(hole newHole: Hole?) {
        guard newHole != hole else { return }
        let previous = hole
        hole = newHole

        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        var borderPath: CGPath?
        var area: CGRect?
        switch newHole {
        case .window(let rect):
            let width: CGFloat = 1.5
            dimPath.addPath(Self.roundedRect(rect, radius: Self.windowCornerRadius))
            borderPath = Self.roundedRect(rect.insetBy(dx: -width / 2, dy: -width / 2), radius: Self.windowCornerRadius + width / 2)
            border.strokeColor = NSColor.controlAccentColor.cgColor
            border.lineWidth = width
        case .area(let rect):
            let width: CGFloat = 1
            area = rect
            borderPath = CGPath(rect: rect.insetBy(dx: -width / 2, dy: -width / 2), transform: nil)
            border.strokeColor = NSColor.white.cgColor
            border.lineWidth = width
        case nil:
            break
        }

        let oldDimPath = dim.presentation()?.path ?? dim.path
        let oldBorderPath = border.presentation()?.path ?? border.path
        if let area {
            layOutAreaDims(around: area)
        } else {
            dim.path = dimPath
        }
        dim.isHidden = area != nil
        for areaDim in areaDims {
            areaDim.isHidden = area == nil
        }
        border.path = borderPath

        switch (previous, newHole) {
        case (.some(.window(_)), .some(.window(_))):
            Self.glide(dim, from: oldDimPath)
            Self.glide(border, from: oldBorderPath)
        case (_, .some(.window(_))):
            dim.removeAllAnimations()
            border.removeAllAnimations()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.08
            border.add(fade, forKey: "opacity")
        default:
            dim.removeAllAnimations()
            border.removeAllAnimations()
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

    /// Keyed by "path", so each new glide replaces the running one and starts from where it is on screen.
    private static func glide(_ layer: CAShapeLayer, from path: CGPath?) {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = path
        animation.duration = 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "path")
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
