import Foundation

public enum ScreenshotFileName {
    /// "zShot 2026-11-26 at 16.23.05", in the given time zone.
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "zShot %04ld-%02ld-%02ld at %02ld.%02ld.%02ld",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// The first free "<name>.png", then "<name> (2).png", "<name> (3).png", ...
    public static func uniqueURL(
        in folder: URL,
        date: Date,
        timeZone: TimeZone = .current,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let base = baseName(for: date, timeZone: timeZone)
        var url = folder.appendingPathComponent(base + ".png")
        var n = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        return url
    }
}
