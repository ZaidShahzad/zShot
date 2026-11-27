import CoreGraphics

/// A frozen image of one display. `frame` is in global points; the image is usually at the display's backing scale.
public struct DisplayImage: @unchecked Sendable {
    public let frame: CGRect
    public let image: CGImage

    public init(frame: CGRect, image: CGImage) {
        self.frame = frame
        self.image = image
    }
}

public struct RenderedScreenshot: @unchecked Sendable {
    public let image: CGImage
    /// Pixels per point.
    public let scale: CGFloat
}

/// One window captured by itself, shown over the frozen displays so the windows covering it are hidden.
/// It shows only inside `visible`, so the menu bar and Dock stay in front of it.
public struct LiftedWindow: Sendable {
    public let image: DisplayImage
    public let visible: [CGRect]

    public init(image: DisplayImage, visible: [CGRect]) {
        self.image = image
        self.visible = visible
    }
}

public enum ScreenshotRenderer {
    public static func render(
        selection: CGRect, displays: [DisplayImage], lifted: LiftedWindow? = nil, annotations: [Annotation]
    ) -> RenderedScreenshot? {
        let visible = displays.filter { $0.frame.intersects(selection) }
        guard let scale = visible.map({ CGFloat($0.image.width) / $0.frame.width }).max(), scale > 0 else { return nil }

        // Snap to whole pixels so frozen pixels are copied, not resampled.
        let minX = (selection.minX * scale).rounded()
        let minY = (selection.minY * scale).rounded()
        let width = Int((selection.maxX * scale).rounded() - minX)
        let height = Int((selection.maxY * scale).rounded() - minY)
        // Drawing in the display's own color space copies pixels without a per-pixel color conversion.
        let displaySpace = visible.first?.image.colorSpace
        guard width > 0, height > 0,
              let space = displaySpace?.model == .rgb ? displaySpace : CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.translateBy(x: -minX, y: -minY)
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .none
        for display in visible {
            context.draw(display.image, in: display.frame)
        }
        if let lifted {
            context.saveGState()
            context.clip(to: lifted.visible)
            context.draw(lifted.image.image, in: lifted.image.frame)
            context.restoreGState()
        }
        AnnotationRenderer.draw(annotations, in: context)

        guard let image = context.makeImage() else { return nil }
        return RenderedScreenshot(image: image, scale: scale)
    }
}
