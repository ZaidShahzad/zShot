import AppKit
import Carbon.HIToolbox

/// The Capture hotkey, registered with Carbon so it needs no Accessibility permission.
@MainActor
final class HotKey {
    private static var current: HotKey?

    private let onPress: @MainActor (TimeInterval) -> Void
    private var ref: EventHotKeyRef?

    /// `onPress` gets the key press time in seconds since boot.
    init(onPress: @escaping @MainActor (TimeInterval) -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
        if status != noErr {
            Log.app.error("InstallEventHandler failed: \(status)")
        }
        HotKey.current = self
    }

    func register(_ combo: HotKeyCombo) {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x7A53_6874), id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            Log.app.error("RegisterEventHotKey failed: \(status)")
        }
    }

    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
        }
        ref = nil
    }

    fileprivate static func pressed(at time: TimeInterval) {
        current?.onPress(time)
    }
}

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    let time = event.map { GetEventTime($0) } ?? ProcessInfo.processInfo.systemUptime
    // Carbon delivers application-target events on the main thread.
    MainActor.assumeIsolated {
        HotKey.pressed(at: time)
    }
    return noErr
}

struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, shiftKey, ...).
    var modifiers: UInt32
    /// Lowercased character the key types, for display and the menu's key equivalent.
    var key: String

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey), key: "s")

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    var display: String {
        let flags = modifierFlags
        var text = ""
        if flags.contains(.control) { text += "\u{2303}" }
        if flags.contains(.option) { text += "\u{2325}" }
        if flags.contains(.shift) { text += "\u{21E7}" }
        if flags.contains(.command) { text += "\u{2318}" }
        return text + key.uppercased()
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return UInt32(modifiers)
    }
}
