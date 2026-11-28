import AppKit

/// The Thumbnail of the latest Screenshot in the corner of its display. Built once and reused.
@MainActor
final class ThumbnailPanel: NSPanel {
    private static let maxSize = NSSize(width: 240, height: 160)
    private static let margin: CGFloat = 16
    private static let visibleNanoseconds: UInt64 = 2_500_000_000

    private let thumbnailView = ThumbnailView(frame: .zero)
    private var dismissTask: Task<Void, Never>?
    private var generation = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = thumbnailView

        thumbnailView.onHover = { [weak self] inside in
            if inside {
                self?.dismissTask?.cancel()
            } else {
                self?.scheduleDismiss()
            }
        }
        thumbnailView.onClick = { [weak self] in
            if let url = self?.thumbnailView.fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            self?.dismiss()
        }
        thumbnailView.onDragEnded = { [weak self] in
            self?.dismiss()
        }
    }

    func show(_ image: NSImage, fileURL: URL?, on screen: NSScreen) {
        let fit = min(Self.maxSize.width / image.size.width, Self.maxSize.height / image.size.height, 1)
        let size = NSSize(width: (image.size.width * fit).rounded(), height: (image.size.height * fit).rounded())
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.maxX - Self.margin - size.width, y: visible.minY + Self.margin, width: size.width, height: size.height)

        generation += 1
        thumbnailView.image = image
        thumbnailView.fileURL = fileURL
        setFrame(frame, display: true)
        invalidateShadow()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.12
        animator().alphaValue = 1
        NSAnimationContext.endGrouping()
        scheduleDismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isVisible else { return }
        let shown = generation
        // Slides toward the screen edge while fading, like it is tucked away rather than switched off.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.18
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeIn)
        NSAnimationContext.current.completionHandler = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.orderOut(nil)
                self.thumbnailView.image = nil
                self.thumbnailView.fileURL = nil
            }
        }
        animator().alphaValue = 0
        animator().setFrame(frame.offsetBy(dx: 28, dy: 0), display: true)
        NSAnimationContext.endGrouping()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.visibleNanoseconds)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

/// Rounded image that can be dragged into other apps as its file, or as an image when it was not saved.
private final class ThumbnailView: NSView, NSDraggingSource {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var fileURL: URL?
    var onHover: (@MainActor (Bool) -> Void)?
    var onClick: (@MainActor () -> Void)?
    var onDragEnded: (@MainActor () -> Void)?

    private var mouseDownEvent: NSEvent?
    private var dragStarted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        layer?.contents = image
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, !dragStarted, let image else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }
        dragStarted = true

        let item: NSDraggingItem
        if let fileURL {
            item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        } else {
            item = NSDraggingItem(pasteboardWriter: image)
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil && !dragStarted {
            onClick?()
        }
        mouseDownEvent = nil
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            onDragEnded?()
        }
    }
}
