import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZShotCore

private struct RGBA: Equatable {
    var r, g, b, a: UInt8
}

private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
    let context = bitmap(width: width, height: height)
    context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func bitmap(width: Int, height: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Pixel at column `x`, row `y` counted from the top of the image.
private func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
    let context = bitmap(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let i = (y * image.width + x) * 4
    return RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
}

private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
private let white = RGBA(r: 255, g: 255, b: 255, a: 255)

@Test func rendersAcrossDisplaysWithDifferentScales() throws {
    let retina = DisplayImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
    let external = DisplayImage(frame: CGRect(x: 100, y: 0, width: 100, height: 100), image: solidImage(width: 100, height: 100, r: 0, g: 0, b: 255))
    let selection = CGRect(x: 50, y: 25, width: 100, height: 50)

    let rendered = try #require(ScreenshotRenderer.render(selection: selection, displays: [retina, external], annotations: []))

    #expect(rendered.scale == 2)
    #expect(rendered.image.width == 200)
    #expect(rendered.image.height == 100)
    #expect(pixel(rendered.image, x: 5, y: 50) == red)
    #expect(pixel(rendered.image, x: 99, y: 50) == red)
    #expect(pixel(rendered.image, x: 100, y: 50) == blue)
    #expect(pixel(rendered.image, x: 195, y: 50) == blue)
}

@Test func placesDisplayImageUpright() throws {
    let context = bitmap(width: 100, height: 100)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
    let display = DisplayImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: context.makeImage()!)

    let rendered = try #require(ScreenshotRenderer.render(selection: display.frame, displays: [display], annotations: []))

    #expect(pixel(rendered.image, x: 50, y: 10) == blue)
    #expect(pixel(rendered.image, x: 50, y: 90) == white)
}

@Test func drawsAnnotationsInGlobalPoints() throws {
    let display = DisplayImage(frame: CGRect(x: 1000, y: 500, width: 100, height: 100), image: solidImage(width: 100, height: 100, r: 255, g: 255, b: 255))
    let line = Annotation(shape: .line(from: CGPoint(x: 1010, y: 550), to: CGPoint(x: 1090, y: 550)), swatch: .red, thickness: .thick)

    let rendered = try #require(ScreenshotRenderer.render(selection: display.frame, displays: [display], annotations: [line]))

    let onLine = pixel(rendered.image, x: 50, y: 50)
    #expect(onLine.r > 200 && onLine.g < 100 && onLine.b < 100)
    #expect(pixel(rendered.image, x: 50, y: 10) == white)
}

@Test func liftedWindowCoversWhatIsUnderIt() throws {
    let display = DisplayImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: solidImage(width: 200, height: 200, r: 255, g: 0, b: 0))
    let window = DisplayImage(frame: CGRect(x: 20, y: 20, width: 50, height: 50), image: solidImage(width: 100, height: 100, r: 0, g: 0, b: 255))

    let rendered = try #require(ScreenshotRenderer.render(selection: display.frame, displays: [display], lifted: window, annotations: []))

    #expect(rendered.scale == 2)
    #expect(pixel(rendered.image, x: 40, y: 159) == blue)
    #expect(pixel(rendered.image, x: 139, y: 60) == blue)
    #expect(pixel(rendered.image, x: 39, y: 159) == red)
    #expect(pixel(rendered.image, x: 140, y: 60) == red)
}

@Test func renderReturnsNilOutsideEveryDisplay() {
    let display = DisplayImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100), image: solidImage(width: 100, height: 100, r: 0, g: 0, b: 0))
    #expect(ScreenshotRenderer.render(selection: CGRect(x: 500, y: 500, width: 10, height: 10), displays: [display], annotations: []) == nil)
}

@Test func pngRoundTripsSizeAndRetinaDPI() throws {
    let image = solidImage(width: 64, height: 32, r: 0, g: 255, b: 0)
    let data = try #require(PNGEncoder.encode(image, scale: 2))

    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    #expect(properties[kCGImagePropertyPixelWidth as String] as? Int == 64)
    #expect(properties[kCGImagePropertyPixelHeight as String] as? Int == 32)
    let dpi = try #require(properties[kCGImagePropertyDPIWidth as String] as? Double)
    #expect(abs(dpi - 144) < 0.5)
}

@Test func fileNameUsesLocalTimeFormat() {
    let zone = TimeZone(identifier: "America/New_York")!
    var parts = DateComponents()
    parts.year = 2026
    parts.month = 11
    parts.day = 26
    parts.hour = 16
    parts.minute = 23
    parts.second = 5
    parts.timeZone = zone
    let date = Calendar(identifier: .gregorian).date(from: parts)!
    #expect(ScreenshotFileName.baseName(for: date, timeZone: zone) == "zShot 2026-11-26 at 16.23.05")
}

@Test func fileNameCollisionsAppendCounter() {
    let folder = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
    let date = Date(timeIntervalSince1970: 0)
    let utc = TimeZone(identifier: "UTC")!
    let taken: Set<String> = ["zShot 1970-01-01 at 00.00.00.png", "zShot 1970-01-01 at 00.00.00 (2).png"]

    let url = ScreenshotFileName.uniqueURL(in: folder, date: date, timeZone: utc) { taken.contains($0.lastPathComponent) }
    #expect(url.lastPathComponent == "zShot 1970-01-01 at 00.00.00 (3).png")

    let free = ScreenshotFileName.uniqueURL(in: folder, date: date, timeZone: utc) { _ in false }
    #expect(free.path == "/tmp/shots/zShot 1970-01-01 at 00.00.00.png")
}
