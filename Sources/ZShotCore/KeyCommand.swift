extension Command {
    /// Maps a key press in Screenshot mode. `characters` is `charactersIgnoringModifiers`, so letters follow the keyboard layout.
    public static func from(keyCode: UInt16, characters: String?, command: Bool, shift: Bool) -> Command? {
        switch keyCode {
        case 53: return .cancel
        case 36, 76: return .finish
        default: break
        }
        guard let key = characters?.lowercased(), key.count == 1 else { return nil }
        if command {
            switch key {
            case "c": return shift ? nil : .finish
            case "z": return shift ? .redo : .undo
            default: return nil
            }
        }
        switch key {
        case "f": return .fullDisplay
        case "a": return .selectTool(.arrow)
        case "l": return .selectTool(.line)
        case "p": return .selectTool(.pen)
        case "r": return .selectTool(.rectangle)
        case "o": return .selectTool(.circle)
        default: return nil
        }
    }
}
