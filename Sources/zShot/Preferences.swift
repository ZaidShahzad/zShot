import Foundation
import ZShotCore

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyCharacter = "hotKeyCharacter"
        static let saveFolder = "saveFolder"
        static let saveToFile = "saveToFile"
        static let copyToClipboard = "copyToClipboard"
        static let tool = "tool"
        static let swatch = "swatch"
        static let thickness = "thickness"
        static let didRegisterLoginItem = "didRegisterLoginItem"
    }

    private let defaults = UserDefaults.standard

    @Published var hotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: Key.hotKeyModifiers)
            defaults.set(hotKey.key, forKey: Key.hotKeyCharacter)
        }
    }

    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) }
    }

    @Published var saveToFile: Bool {
        didSet { defaults.set(saveToFile, forKey: Key.saveToFile) }
    }

    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) }
    }

    var toolStyle: ToolStyle {
        didSet {
            defaults.set(toolStyle.tool.rawValue, forKey: Key.tool)
            defaults.set(toolStyle.swatch.rawValue, forKey: Key.swatch)
            defaults.set(toolStyle.thickness.rawValue, forKey: Key.thickness)
        }
    }

    var didRegisterLoginItem: Bool {
        get { defaults.bool(forKey: Key.didRegisterLoginItem) }
        set { defaults.set(newValue, forKey: Key.didRegisterLoginItem) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Key.saveToFile: true, Key.copyToClipboard: true])

        if let key = defaults.string(forKey: Key.hotKeyCharacter), !key.isEmpty {
            hotKey = HotKeyCombo(
                keyCode: UInt32(defaults.integer(forKey: Key.hotKeyCode)),
                modifiers: UInt32(defaults.integer(forKey: Key.hotKeyModifiers)),
                key: key)
        } else {
            hotKey = .default
        }

        if let path = defaults.string(forKey: Key.saveFolder) {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Pictures")
            saveFolder = pictures.appendingPathComponent("zShot", isDirectory: true)
        }

        saveToFile = defaults.bool(forKey: Key.saveToFile)
        copyToClipboard = defaults.bool(forKey: Key.copyToClipboard)

        let fallback = ToolStyle()
        toolStyle = ToolStyle(
            tool: defaults.string(forKey: Key.tool).flatMap(Tool.init(rawValue:)) ?? fallback.tool,
            swatch: defaults.string(forKey: Key.swatch).flatMap(Swatch.init(rawValue:)) ?? fallback.swatch,
            thickness: defaults.string(forKey: Key.thickness).flatMap(Thickness.init(rawValue:)) ?? fallback.thickness)
    }
}
