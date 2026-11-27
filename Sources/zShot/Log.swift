import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "io.github.zaidshahzad.zshot", category: "app")

    /// `start` is seconds since boot, the clock of `ProcessInfo.systemUptime` and Carbon event times.
    static func timing(_ label: String, since start: TimeInterval) {
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        app.notice("\(label, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public) ms")
    }
}
