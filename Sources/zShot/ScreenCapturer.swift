import AppKit
import ScreenCaptureKit
import ZShotCore

/// Freezes every display with ScreenCaptureKit, leaving out zShot's own windows.
@MainActor
final class ScreenCapturer {
    /// Built once per display and never mutated afterwards, so sharing it with capture tasks is safe.
    private struct Target: @unchecked Sendable {
        let frame: CGRect
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    private var targets: [Target] = []

    /// Call after zShot's windows exist and whenever the screens change.
    func refresh() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let pid = getpid()
            let ownApp = content.applications.first { $0.processID == pid }
            let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }

            var targets: [Target] = []
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let display = content.displays.first(where: { $0.displayID == number.uint32Value })
                else { continue }

                let filter: SCContentFilter
                if let ownApp {
                    filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
                } else {
                    filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                }
                let configuration = SCStreamConfiguration()
                configuration.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
                configuration.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
                configuration.showsCursor = false
                configuration.captureResolution = .best
                targets.append(Target(frame: screen.frame, filter: filter, configuration: configuration))
            }
            self.targets = targets
        } catch {
            targets = []
            Log.app.error("Shareable content unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// nil when capture fails, which almost always means Screen Recording permission is missing.
    func freezeAll() async -> [DisplayImage]? {
        if targets.isEmpty {
            await refresh()
        }
        let targets = self.targets
        guard !targets.isEmpty else { return nil }
        do {
            return try await withThrowingTaskGroup(of: DisplayImage.self, returning: [DisplayImage].self) { group in
                for target in targets {
                    group.addTask {
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: target.filter, configuration: target.configuration)
                        return DisplayImage(frame: target.frame, image: image)
                    }
                }
                var images: [DisplayImage] = []
                for try await image in group {
                    images.append(image)
                }
                return images
            }
        } catch {
            self.targets = []
            Log.app.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Owns Screen Recording permission. Only `handleMissing()` makes macOS prompt, and only once ever.
@MainActor
enum ScreenRecordingPermission {
    private static let didRequestKey = "didRequestScreenRecording"
    private static var knownGranted = false
    private static var isAlertShown = false

    /// Never prompts. Once true it is remembered, so later hotkeys skip the check.
    static var isGranted: Bool {
        if !knownGranted {
            knownGranted = CGPreflightScreenCaptureAccess()
        }
        return knownGranted
    }

    /// The first time ever, asks macOS. After that, shows zShot's own alert.
    static func handleMissing() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: didRequestKey) {
            showMissingAlert()
        } else {
            defaults.set(true, forKey: didRequestKey)
            CGRequestScreenCaptureAccess()
        }
    }

    static func captureFailed() {
        knownGranted = false
        showMissingAlert()
    }

    private static func showMissingAlert() {
        guard !isAlertShown else { return }
        isAlertShown = true
        defer { isAlertShown = false }

        let alert = NSAlert()
        alert.messageText = "zShot can't see your screen yet"
        alert.informativeText = """
            Turn on zShot in System Settings > Privacy & Security > Screen & System Audio Recording, \
            then quit and reopen zShot. macOS only applies the change after a restart.

            If zShot is already on there, a rebuilt copy counts as a new app. \
            Select zShot, remove it with the minus button, then try again.
            """
        alert.addButton(withTitle: "Quit and Reopen")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            relaunch()
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            Log.app.error("Relaunching zShot failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
