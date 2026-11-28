import AppKit
import ZShotCore

/// Tool, color, and thickness picker shown next to the Selection.
@MainActor
final class Toolbar: NSView {
    var onCommand: (@MainActor (Command) -> Void)?

    private var toolButtons: [NSButton] = []
    private var swatchButtons: [NSButton] = []
    private var thicknessButtons: [NSButton] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        toolButtons = Tool.allCases.enumerated().map { index, tool in
            button(image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.rawValue), tag: index, action: #selector(toolPressed))
        }
        swatchButtons = Swatch.allCases.enumerated().map { index, swatch in
            button(image: Self.swatchImage(swatch), tag: index, action: #selector(swatchPressed))
        }
        thicknessButtons = Thickness.allCases.enumerated().map { index, thickness in
            button(image: Self.thicknessImage(thickness), tag: index, action: #selector(thicknessPressed))
        }
        let copy = button(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy"), tag: 0, action: #selector(copyPressed))
        let close = button(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close"), tag: 0, action: #selector(closePressed))

        let groups: [[NSView]] = [toolButtons, swatchButtons, thicknessButtons, [copy, close]]
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        for group in groups {
            for view in group {
                stack.addArrangedSubview(view)
            }
            if let last = group.last {
                stack.setCustomSpacing(12, after: last)
            }
        }
        setFrameSize(stack.fittingSize)
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        addSubview(stack)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(style: ToolStyle) {
        highlight(toolButtons, selected: Tool.allCases.firstIndex(of: style.tool))
        highlight(swatchButtons, selected: Swatch.allCases.firstIndex(of: style.swatch))
        highlight(thicknessButtons, selected: Thickness.allCases.firstIndex(of: style.thickness))
    }

    private func highlight(_ buttons: [NSButton], selected: Int?) {
        let selectedColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        for (index, button) in buttons.enumerated() {
            button.layer?.backgroundColor = index == selected ? selectedColor : nil
        }
    }

    private func button(image: NSImage?, tag: Int, action: Selector) -> NSButton {
        let button = ToolbarButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.image = image
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.tag = tag
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func toolPressed(_ sender: NSButton) {
        onCommand?(.selectTool(Tool.allCases[sender.tag]))
    }

    @objc private func swatchPressed(_ sender: NSButton) {
        onCommand?(.selectSwatch(Swatch.allCases[sender.tag]))
    }

    @objc private func thicknessPressed(_ sender: NSButton) {
        onCommand?(.selectThickness(Thickness.allCases[sender.tag]))
    }

    @objc private func copyPressed(_ sender: NSButton) {
        onCommand?(.finish)
    }

    @objc private func closePressed(_ sender: NSButton) {
        onCommand?(.cancel)
    }

    private static func swatchImage(_ swatch: Swatch) -> NSImage {
        let color = swatch.cgColor
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let circle = rect.insetBy(dx: 1.5, dy: 1.5)
            context.setFillColor(color)
            context.fillEllipse(in: circle)
            context.setStrokeColor(NSColor.gray.cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: circle)
            return true
        }
    }

    private static func thicknessImage(_ thickness: Thickness) -> NSImage {
        let width = thickness.lineWidth
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Clicks work on the first press even though zShot is never the active app.
private final class ToolbarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Tool {
    /// The SF Symbol for the Tool, shared by its Toolbar button and its pointer.
    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "scribble"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        }
    }
}
