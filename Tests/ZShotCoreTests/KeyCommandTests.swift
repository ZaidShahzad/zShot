import Testing
import ZShotCore

@Test func keyMapping() {
    #expect(Command.from(keyCode: 53, characters: "\u{1b}", command: false, shift: false) == .cancel)
    #expect(Command.from(keyCode: 36, characters: "\r", command: false, shift: false) == .finish)
    #expect(Command.from(keyCode: 76, characters: "\u{3}", command: false, shift: false) == .finish)
    #expect(Command.from(keyCode: 8, characters: "c", command: true, shift: false) == .finish)
    #expect(Command.from(keyCode: 6, characters: "z", command: true, shift: false) == .undo)
    #expect(Command.from(keyCode: 6, characters: "Z", command: true, shift: true) == .redo)
    #expect(Command.from(keyCode: 3, characters: "f", command: false, shift: false) == .fullDisplay)
    #expect(Command.from(keyCode: 0, characters: "a", command: false, shift: false) == .selectTool(.arrow))
    #expect(Command.from(keyCode: 37, characters: "L", command: false, shift: true) == .selectTool(.line))
    #expect(Command.from(keyCode: 35, characters: "p", command: false, shift: false) == .selectTool(.pen))
    #expect(Command.from(keyCode: 15, characters: "r", command: false, shift: false) == .selectTool(.rectangle))
    #expect(Command.from(keyCode: 31, characters: "o", command: false, shift: false) == .selectTool(.circle))
}

@Test func keyMappingFollowsLayoutCharactersNotKeyCodes() {
    // On AZERTY the key with ANSI code 12 (Q) types "a".
    #expect(Command.from(keyCode: 12, characters: "a", command: false, shift: false) == .selectTool(.arrow))
}

@Test func unmappedKeysReturnNil() {
    #expect(Command.from(keyCode: 0, characters: "a", command: true, shift: false) == nil)
    #expect(Command.from(keyCode: 8, characters: "c", command: true, shift: true) == nil)
    #expect(Command.from(keyCode: 7, characters: "x", command: false, shift: false) == nil)
    #expect(Command.from(keyCode: 8, characters: "c", command: false, shift: false) == nil)
    #expect(Command.from(keyCode: 122, characters: nil, command: false, shift: false) == nil)
}
