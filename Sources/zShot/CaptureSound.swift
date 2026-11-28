import AppKit

/// The shutter sound macOS's own screenshots make, played from the system's copy so it matches 1:1.
@MainActor
enum CaptureSound {
    private static let candidates = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
    ]

    /// Loaded at launch so the first Screenshot doesn't wait on disk.
    private static let sound: NSSound? = candidates.lazy
        .compactMap { NSSound(contentsOf: URL(fileURLWithPath: $0), byReference: true) }
        .first

    static func preload() {
        _ = sound
    }

    /// Plays without blocking. Silent when "Play user interface sound effects" is off, like the system's screenshots.
    static func play() {
        guard userInterfaceSoundsEnabled, let sound else { return }
        sound.stop()
        sound.play()
    }

    private static var userInterfaceSoundsEnabled: Bool {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (global?["com.apple.sound.uiaudio.enabled"] as? NSNumber)?.boolValue ?? true
    }
}
