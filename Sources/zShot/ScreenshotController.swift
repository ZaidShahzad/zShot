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
    /// The menu bar and Dock strips of every display, in front of every window.
    private var screenEdges: [CGRect] = []
    private var lift: Lift?

    /// The window a click chose while other windows cover part of it, captured by itself.
    private struct Lift {
        /// The window as it looks once lifted in front of the windows covering it.
        let target: WindowTarget
        /// Yields nil on failure.
        let task: Task<LiftedWindow?, Never>
        /// Whether the panels show the capture yet.
        var isShown = false
    }
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
        let displays = panels.map { $0.screenFrame }
        session = ScreenshotSession(displays: displays, windows: [], style: preferences.toolStyle, mouse: mouse)
        render()
        for panel in panels {
            panel.show()
        }
        (panels.first(where: { $0.screenFrame.contains(mouse) }) ?? fallbackPanel).makeKey()
        ScreenshotCursor.shared.set()
        DispatchQueue.main.async {
            Log.timing("hotkey\u{2192}shown", since: hotKeyTime)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // The Dock's and menu bar's own windows can span the whole display, which reads as an invisible overlay,
        // so the strips they take are put in front of every window instead.
        screenEdges = panels.flatMap { WindowRegions.subtract($0.displayScreen.visibleFrame, from: $0.screenFrame) }
        let edgeWindows = screenEdges.map { ScreenWindow(id: 0, frame: $0, isTarget: false) }
        Task { [weak self] in
            let windows = await Task.detached(priority: .userInitiated) {
                WindowRegions.targets(edgeWindows + WindowList.snapshot(primaryHeight: primaryHeight), displays: displays)
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
            updateLift()
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
        // Outlined as the click found it until the lifted capture shows, then as lifted.
        let selectedWindow = lift?.isShown == true ? lift?.target : session.selectedWindow
        for panel in panels {
            panel.render(session, selectedWindow: selectedWindow, showsToolbar: panel === host)
        }
    }

    /// The panel whose display holds the Selection's bottom-right corner.
    private func toolbarPanel(for session: ScreenshotSession) -> OverlayPanel? {
        guard case .annotating(let selection, _) = session.phase else { return nil }
        let corner = CGPoint(x: selection.maxX - 1, y: selection.minY + 1)
        return panels.first(where: { $0.screenFrame.contains(corner) }) ?? panels.first
    }

    /// Starts lifting the chosen window when it is partly covered, and drops the lift when the Selection moves off it.
    /// Never blocks input: the capture runs on its own and the panels show it when it lands.
    private func updateLift() {
        let target = session?.selectedWindow?.lifted(under: screenEdges)
        guard target != lift?.target else { return }
        dropLift()
        guard let target else { return }

        let entry = self.entry
        let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let capturer = self.capturer
        let task = Task { [weak self] () -> LiftedWindow? in
            let image = await capturer.captureWindow(id: target.id, scale: scale)
            let lifted = image.map { LiftedWindow(image: $0, visible: target.visible) }
            guard let self, let lifted, !Task.isCancelled, self.entry == entry, self.session != nil,
                  self.lift?.target == target
            else { return lifted }
            for panel in self.panels {
                panel.setLifted(lifted)
            }
            self.lift?.isShown = true
            self.render()
            return lifted
        }
        lift = Lift(target: target, task: task)
    }

    private func dropLift() {
        lift?.task.cancel()
        lift = nil
        for panel in panels {
            panel.setLifted(nil)
        }
    }

    private func exitScreenshotMode() {
        session = nil
        freezeTask?.cancel()
        freezeTask = nil
        dropLift()
        hidePanels()
    }

    private func hidePanels() {
        for panel in panels {
            panel.orderOut(nil)
            panel.setFrozenImage(nil)
            panel.setLifted(nil)
        }
    }

    private func finish(selection: CGRect, annotations: [Annotation]) {
        let start = ProcessInfo.processInfo.systemUptime
        let screen = session.flatMap { toolbarPanel(for: $0) }?.displayScreen ?? NSScreen.main
        let freeze = freezeTask
        let liftTask = lift?.task
        session = nil
        freezeTask = nil
        lift = nil
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
            // Usually landed already, about 50 ms after the click. A failed lift renders without it.
            let lifted: LiftedWindow? = await liftTask?.value ?? nil
            let rendered = await Task.detached(priority: .userInitiated) {
                ScreenshotRenderer.render(selection: selection, displays: images, lifted: lifted, annotations: annotations)
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
