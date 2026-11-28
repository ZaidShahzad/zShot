import AppKit
import ZShotCore

/// Tool picker, color and thickness buttons, Copy, and Close, shown next to the Selection.
/// The color and thickness buttons each show the current choice and open `choices` with every option.
@MainActor
final class Toolbar: NSView {
    var onCommand: (@MainActor (Command) -> Void)?
    /// The row of colors or thicknesses above its button. The owner adds it to the Toolbar's superview, so it can sit outside
    /// the Toolbar, and routes clicks on it like clicks on the Toolbar.
    let choices = ChoiceStrip()

    /// The Toolbar buttons that open `choices`, in order.
    private enum Picker: Int, CaseIterable {
        case swatch, thickness
    }

    private var toolButtons: [NSButton] = []
    private var pickerButtons: [NSButton] = []
    /// Shown in `choices` while their Picker is open.
    private var swatchButtons: [NSButton] = []
    private var thicknessButtons: [NSButton] = []
    private var openPicker: Picker?
    private var shownStyle: ToolStyle?

    init() {
        super.init(frame: .zero)
        applyBarStyle()

        toolButtons = Tool.allCases.enumerated().map { index, tool in
            button(image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.rawValue), tag: index, action: #selector(toolPressed))
        }
        pickerButtons = Picker.allCases.map { picker in
            button(image: nil, tag: picker.rawValue, action: #selector(pickerPressed))
        }
        swatchButtons = Swatch.allCases.enumerated().map { index, swatch in
            button(image: Self.swatchImage(swatch), tag: index, action: #selector(swatchPressed))
        }
        thicknessButtons = Thickness.allCases.enumerated().map { index, thickness in
            button(image: Self.thicknessImage(thickness), tag: index, action: #selector(thicknessPressed))
        }
        let copy = button(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy"), tag: 0, action: #selector(copyPressed))
        let close = button(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close"), tag: 0, action: #selector(closePressed))

        let groups: [[NSView]] = [toolButtons, pickerButtons, [copy, close]]
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
        guard style != shownStyle else { return }
        shownStyle = style
        highlight(toolButtons, selected: Tool.allCases.firstIndex(of: style.tool))
        highlight(swatchButtons, selected: Swatch.allCases.firstIndex(of: style.swatch))
        highlight(thicknessButtons, selected: Thickness.allCases.firstIndex(of: style.thickness))
        pickerButtons[Picker.swatch.rawValue].image = Self.swatchImage(style.swatch)
        pickerButtons[Picker.thickness.rawValue].image = Self.thicknessImage(style.thickness)
    }

    /// Hides `choices`. Does nothing when they are already hidden.
    func closeChoices() {
        guard openPicker != nil else { return }
        openPicker = nil
        choices.isHidden = true
        highlight(pickerButtons, selected: nil)
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

    /// Centered above `button`, kept on the display; below the Toolbar when there is no room above.
    private func placeChoices(above button: NSButton) {
        guard let container = choices.superview else { return }
        let gap: CGFloat = 6
        let size = choices.frame.size
        let anchor = button.convert(button.bounds, to: container)
        let bar = convert(bounds, to: container)
        let area = container.bounds
        var y = bar.maxY + gap
        if y + size.height > area.maxY {
            y = bar.minY - gap - size.height
        }
        let x = min(max(anchor.midX - size.width / 2, area.minX + gap), area.maxX - size.width - gap)
        choices.setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func toolPressed(_ sender: NSButton) {
        closeChoices()
        onCommand?(.selectTool(Tool.allCases[sender.tag]))
    }

    /// Opens its Picker's choices, or closes them when they are already open.
    @objc private func pickerPressed(_ sender: NSButton) {
        guard let picker = Picker(rawValue: sender.tag) else { return }
        guard openPicker != picker else {
            closeChoices()
            return
        }
        openPicker = picker
        highlight(pickerButtons, selected: picker.rawValue)
        choices.show(picker == .swatch ? swatchButtons : thicknessButtons)
        placeChoices(above: sender)
    }

    @objc private func swatchPressed(_ sender: NSButton) {
        closeChoices()
        onCommand?(.selectSwatch(Swatch.allCases[sender.tag]))
    }

    @objc private func thicknessPressed(_ sender: NSButton) {
        closeChoices()
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

/// A row of colors or thicknesses that a Toolbar button opens. Hidden until then.
@MainActor
final class ChoiceStrip: NSView {
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        applyBarStyle()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        addSubview(stack)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows `buttons` in place of any shown before, sized to fit them.
    func show(_ buttons: [NSButton]) {
        for view in stack.arrangedSubviews {
            view.removeFromSuperview()
        }
        for button in buttons {
            stack.addArrangedSubview(button)
        }
        setFrameSize(stack.fittingSize)
        stack.frame = bounds
        isHidden = false
    }
}

private extension NSView {
    /// The Toolbar's look, shared by its choices.
    func applyBarStyle() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
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
