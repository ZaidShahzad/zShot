import AppKit
import ZShotCore

/// Owns Screenshot mode: the prebuilt overlay panels, the session, and finishing into a Screenshot.
@MainActor
final class ScreenshotController {
    private let preferences: Preferences
    private let capturer: ScreenCapturer
    private let thumbnail = ThumbnailPanel()
    private var panels: [OverlayPanel] = []
    private var session: ScreenshotSession?
    private var freezeTask: Task<[DisplayImage]?, Never>?
    /// Counts entries into Screenshot mode, so late results from an earlier one are ignored.
    private var entry = 0

    init(preferences: Preferences, capturer: ScreenCapturer) {
        self.preferences = preferences
        self.capturer = capturer
        rebuildPanels()
    }

    func rebuildPanels() {
        if session != nil {
            exitScreenshotMode()
        }
        for panel in panels {
            panel.close()
        }
        panels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(screen: screen)
            panel.onInput = { [weak self] input in
                self?.handle(input)
            }
            return panel
        }
    }

    /// `hotKeyTime` is seconds since boot when the Capture hotkey was pressed.
    func enter(hotKeyTime: TimeInterval) {
        guard session == nil, let fallbackPanel = panels.first else { return }
        guard ScreenRecordingPermission.isGranted else {
            ScreenRecordingPermission.handleMissing()
            return
        }
        entry += 1
        let entry = self.entry
        let mouse = NSEvent.mouseLocation
        session = ScreenshotSession(displays: panels.map { $0.screenFrame }, windows: [], style: preferences.toolStyle, mouse: mouse)
        render()
        for panel in panels {
            panel.show()
        }
        (panels.first(where: { $0.screenFrame.contains(mouse) }) ?? fallbackPanel).makeKey()
        NSCursor.crosshair.set()
        DispatchQueue.main.async {
            Log.timing("hotkey\u{2192}shown", since: hotKeyTime)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        Task { [weak self] in
            let windows = await Task.detached(priority: .userInitiated) {
                WindowList.snapshot(primaryHeight: primaryHeight)
            }.value
            guard let self, self.entry == entry, self.session != nil else { return }
            self.session?.setWindows(windows)
            self.render()
        }

        let capturer = self.capturer
        freezeTask = Task { [weak self] in
            let images = await capturer.freezeAll()
            guard let self, self.entry == entry, self.session != nil else { return images }
            guard let images else {
                self.exitScreenshotMode()
                ScreenRecordingPermission.captureFailed()
                return nil
            }
            for panel in self.panels {
                panel.setFrozenImage(images.first(where: { $0.frame == panel.screenFrame })?.image)
            }
            return images
        }
    }

    private func handle(_ input: Input) {
        guard session != nil else { return }
        let outcome = session?.handle(input)
        if let style = session?.style, style != preferences.toolStyle {
            preferences.toolStyle = style
        }
        switch outcome {
        case nil:
            render()
        case .cancel?:
            exitScreenshotMode()
        case .finish(let selection, let annotations)?:
            finish(selection: selection, annotations: annotations)
        }
    }

    private func render() {
        guard let session else { return }
        let host = toolbarPanel(for: session)
        for panel in panels {
            panel.render(session, showsToolbar: panel === host)
        }
    }

    /// The panel whose display holds the Selection's bottom-right corner.
    private func toolbarPanel(for session: ScreenshotSession) -> OverlayPanel? {
        guard case .annotating(let selection, _) = session.phase else { return nil }
        let corner = CGPoint(x: selection.maxX - 1, y: selection.minY + 1)
        return panels.first(where: { $0.screenFrame.contains(corner) }) ?? panels.first
    }

    private func exitScreenshotMode() {
        session = nil
        freezeTask?.cancel()
        freezeTask = nil
        hidePanels()
    }

    private func hidePanels() {
        for panel in panels {
            panel.orderOut(nil)
            panel.setFrozenImage(nil)
        }
    }

    private func finish(selection: CGRect, annotations: [Annotation]) {
        let start = ProcessInfo.processInfo.systemUptime
        let screen = session.flatMap { toolbarPanel(for: $0) }?.displayScreen ?? NSScreen.main
        let freeze = freezeTask
        session = nil
        freezeTask = nil
        hidePanels()

        let copy = preferences.copyToClipboard
        let save = preferences.saveToFile
        let folder = preferences.saveFolder
        let date = Date()
        Task { [weak self] in
            guard let images = await freeze?.value else {
                ScreenRecordingPermission.captureFailed()
                return
            }
            let rendered = await Task.detached(priority: .userInitiated) {
                ScreenshotRenderer.render(selection: selection, displays: images, annotations: annotations)
            }.value
            guard let rendered else {
                Log.app.error("Rendering the Screenshot failed")
                return
            }
            Log.timing("finish\u{2192}rendered", since: start)

            let promise = copy ? Output.copyToClipboard() : nil
            if copy {
                Log.timing("finish\u{2192}clipboard", since: start)
            }
            let png = await Task.detached(priority: .userInitiated) {
                PNGEncoder.encode(rendered.image, scale: rendered.scale)
            }.value
            promise?.fulfill(png)
            Log.timing("finish\u{2192}png", since: start)
            guard let png else {
                Log.app.error("Encoding the Screenshot failed")
                return
            }

            var fileURL: URL?
            if save {
                fileURL = await Task.detached(priority: .utility) { () -> URL? in
                    do {
                        return try Output.save(png, in: folder, date: date)
                    } catch {
                        Log.app.error("Saving the Screenshot failed: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }.value
            }

            guard let self, let screen else { return }
            let pointSize = NSSize(
                width: CGFloat(rendered.image.width) / rendered.scale,
                height: CGFloat(rendered.image.height) / rendered.scale)
            self.thumbnail.show(NSImage(cgImage: rendered.image, size: pointSize), fileURL: fileURL, on: screen)
        }
    }
}
