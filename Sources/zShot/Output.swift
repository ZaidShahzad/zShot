import AppKit
import ZShotCore

enum Output {
    @MainActor
    static func copyToClipboard(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    /// Writes into `folder`, creating it if needed, under a name that does not overwrite an earlier Screenshot.
    static func save(_ png: Data, in folder: URL, date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = ScreenshotFileName.uniqueURL(in: folder, date: date)
        try png.write(to: url, options: .atomic)
        return url
    }
}
