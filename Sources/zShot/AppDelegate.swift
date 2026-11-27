import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let capturer = ScreenCapturer()
    private var controller: ScreenshotController?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var takeScreenshotItem: NSMenuItem?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreenRecordingPermission.requestIfNeeded()

        let controller = ScreenshotController(preferences: preferences, capturer: capturer)
        self.controller = controller
        hotKey = HotKey { [weak controller] time in
            controller?.enter(hotKeyTime: time)
        }
        buildStatusItem()
        registerHotKey()
        registerLoginItemOnFirstLaunch()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let capturer = self.capturer
        Task {
            await capturer.refresh()
        }
    }

    private func registerHotKey() {
        hotKey?.register(preferences.hotKey)
        takeScreenshotItem?.keyEquivalent = preferences.hotKey.key
        takeScreenshotItem?.keyEquivalentModifierMask = preferences.hotKey.modifierFlags
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "zShot")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        let take = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "")
        menu.addItem(take)
        menu.addItem(NSMenuItem(title: "Open zShot Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit zShot", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
        takeScreenshotItem = take
    }

    private func registerLoginItemOnFirstLaunch() {
        guard !preferences.didRegisterLoginItem else { return }
        preferences.didRegisterLoginItem = true
        do {
            try SMAppService.mainApp.register()
        } catch {
            Log.app.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func takeScreenshot() {
        controller?.enter(hotKeyTime: ProcessInfo.processInfo.systemUptime)
    }

    @objc private func openFolder() {
        let folder = preferences.saveFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.app.error("Creating the zShot folder failed: \(error.localizedDescription, privacy: .public)")
        }
        NSWorkspace.shared.open(folder)
    }

    @objc private func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(
                preferences: preferences,
                suspendHotKey: { [weak self] in self?.hotKey?.unregister() },
                resumeHotKey: { [weak self] in self?.registerHotKey() })
        }
        settings?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func screensChanged() {
        controller?.rebuildPanels()
        let capturer = self.capturer
        Task {
            await capturer.refresh()
        }
    }
}
