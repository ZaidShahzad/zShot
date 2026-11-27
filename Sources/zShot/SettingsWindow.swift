import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let preferences: Preferences
    private let suspendHotKey: @MainActor () -> Void
    private let resumeHotKey: @MainActor () -> Void
    private var window: NSWindow?

    /// The Capture hotkey is suspended while the recorder listens, so pressing it is recorded instead of starting a Screenshot.
    init(preferences: Preferences, suspendHotKey: @escaping @MainActor () -> Void, resumeHotKey: @escaping @MainActor () -> Void) {
        self.preferences = preferences
        self.suspendHotKey = suspendHotKey
        self.resumeHotKey = resumeHotKey
    }

    func show() {
        if window == nil {
            let view = SettingsView(preferences: preferences, suspendHotKey: suspendHotKey, resumeHotKey: resumeHotKey)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "zShot Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let suspendHotKey: @MainActor () -> Void
    let resumeHotKey: @MainActor () -> Void
    @State private var startsAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            LabeledContent("Capture hotkey") {
                HotKeyRecorder(combo: preferences.hotKey, onStart: suspendHotKey) { combo in
                    if let combo {
                        preferences.hotKey = combo
                    }
                    resumeHotKey()
                }
                .frame(width: 140, height: 24)
            }
            LabeledContent("Save folder") {
                HStack {
                    Text(preferences.saveFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose\u{2026}") { chooseFolder() }
                }
            }
            Toggle("Save to file", isOn: $preferences.saveToFile)
            Toggle("Copy to clipboard", isOn: $preferences.copyToClipboard)
            Toggle("Start at login", isOn: $startsAtLogin)
                .onChange(of: startsAtLogin) { _, on in setStartsAtLogin(on) }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            preferences.saveFolder = url
        }
    }

    private func setStartsAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        let enabled = SMAppService.mainApp.status == .enabled
        if enabled != startsAtLogin {
            startsAtLogin = enabled
        }
    }
}

/// Click, then press a key with Command, Option, or Control. Esc or clicking away cancels.
private struct HotKeyRecorder: NSViewRepresentable {
    let combo: HotKeyCombo
    let onStart: @MainActor () -> Void
    let onFinish: @MainActor (HotKeyCombo?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(frame: .zero)
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.toggleRecording)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.combo = combo
        button.onStart = onStart
        button.onFinish = onFinish
        button.refreshTitle()
    }
}

private final class RecorderButton: NSButton {
    var combo = HotKeyCombo.default
    var onStart: (@MainActor () -> Void)?
    var onFinish: (@MainActor (HotKeyCombo?) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        title = isRecording ? "Type shortcut\u{2026}" : combo.display
    }

    @objc func toggleRecording() {
        if isRecording {
            finish(nil)
        } else {
            isRecording = true
            refreshTitle()
            _ = window?.makeFirstResponder(self)
            onStart?()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            record(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            finish(nil)
        }
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            finish(nil)
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty
        else {
            NSSound.beep()
            return
        }
        finish(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: HotKeyCombo.carbonModifiers(flags), key: key))
    }

    private func finish(_ newCombo: HotKeyCombo?) {
        isRecording = false
        if let newCombo {
            combo = newCombo
        }
        refreshTitle()
        onFinish?(newCombo)
    }
}
