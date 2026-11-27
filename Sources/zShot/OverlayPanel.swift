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
    private let toolbar = Toolbar()
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
        backdrop.addSubview(toolbar)
        contentView = backdrop
        initialFirstResponder = backdrop

        toolbar.isHidden = true
        toolbar.onCommand = { [weak self] command in
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

        var hole: CGRect?
        var selection: CGRect?
        var selectingSize: CGSize?
        switch session.phase {
        case .choosing(let hover), .pressing(_, let hover):
            hole = hover
        case .selecting(let anchor, let current):
            hole = Geometry.rect(from: anchor, to: current)
            selectingSize = hole?.size
        case .annotating(let rect, _):
            hole = rect
            selection = rect
        }
        let isWindowHover = selection == nil && selectingSize == nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chrome.update(
            hole: hole.map(local),
            borderColor: isWindowHover ? NSColor.controlAccentColor.cgColor : NSColor.white.cgColor,
            borderWidth: isWindowHover ? 2 : 1)
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
            toolbar.update(style: session.style)
            toolbar.setFrameOrigin(toolbarOrigin(for: local(selection)))
            toolbar.isHidden = false
        } else {
            toolbar.isHidden = true
        }
    }

    /// Below the Selection, right aligned; above it if there is no room; inside its bottom edge otherwise.
    private func toolbarOrigin(for selection: CGRect) -> CGPoint {
        let gap: CGFloat = 8
        let size = toolbar.frame.size
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
            mouseDownInToolbar = !toolbar.isHidden && toolbar.frame.contains(event.locationInWindow)
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

/// Dims everything outside the hole and borders it. Plain layers, so moving them costs no redraw.
private final class ChromeView: NSView {
    private let dims: [CALayer] = (0..<4).map { _ in CALayer() }
    private let border = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let dim = NSColor.black.withAlphaComponent(0.4).cgColor
        for layer in dims {
            layer.backgroundColor = dim
            self.layer?.addSublayer(layer)
        }
        self.layer?.addSublayer(border)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(hole: CGRect?, borderColor: CGColor, borderWidth: CGFloat) {
        let b = bounds
        let h = hole?.intersection(b) ?? .null
        if h.isNull {
            dims[0].frame = b
            for layer in dims.dropFirst() { layer.frame = .zero }
        } else {
            dims[0].frame = CGRect(x: b.minX, y: h.maxY, width: b.width, height: b.maxY - h.maxY)
            dims[1].frame = CGRect(x: b.minX, y: b.minY, width: b.width, height: h.minY - b.minY)
            dims[2].frame = CGRect(x: b.minX, y: h.minY, width: h.minX - b.minX, height: h.height)
            dims[3].frame = CGRect(x: h.maxX, y: h.minY, width: b.maxX - h.maxX, height: h.height)
        }
        if let hole {
            border.isHidden = false
            border.frame = hole.insetBy(dx: -borderWidth, dy: -borderWidth)
            border.borderColor = borderColor
            border.borderWidth = borderWidth
        } else {
            border.isHidden = true
        }
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
