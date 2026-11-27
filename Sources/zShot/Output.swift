import AppKit
import ZShotCore

enum Output {
    /// Keeps the latest clipboard promise alive until the next Screenshot replaces it.
    @MainActor private static var clipboardPromise: PromisedPNG?

    /// Puts a PNG promise on the clipboard right away, so finishing doesn't wait for PNG encoding.
    /// A paste that arrives before `fulfill` waits for the encoder, which is already running.
    @MainActor
    static func copyToClipboard() -> PromisedPNG {
        let promise = PromisedPNG()
        let item = NSPasteboardItem()
        item.setDataProvider(promise, forTypes: [.png])
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        clipboardPromise = promise
        return promise
    }

    /// Writes into `folder`, creating it if needed, under a name that does not overwrite an earlier Screenshot.
    static func save(_ png: Data, in folder: URL, date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = ScreenshotFileName.uniqueURL(in: folder, date: date)
        try png.write(to: url, options: .atomic)
        return url
    }
}

final class PromisedPNG: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    /// Written once before `ready` is signaled, read only after waiting on it.
    private var png: Data?

    func fulfill(_ png: Data?) {
        self.png = png
        ready.signal()
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        ready.wait()
        ready.signal()
        if let png {
            item.setData(png, forType: type)
        }
    }
}
