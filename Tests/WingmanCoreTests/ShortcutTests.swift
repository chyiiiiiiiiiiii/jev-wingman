import Testing
@testable import WingmanCore

// Carbon modifier masks: ⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096. Space is key code 49.

@Test func readsRaycastsGlobalHotkey() {
    #expect(Shortcut(raycast: "Option-49") == Shortcut(keyCode: 49, carbonModifiers: 2048))
    #expect(Shortcut(raycast: "Command-Shift-49") == Shortcut(keyCode: 49, carbonModifiers: 768))
    #expect(Shortcut(raycast: "") == nil)
}

@Test func readsAShortcutSavedByTheKeyboardShortcutsLibrary() {
    // ChatGPT's launcher, as the KeyboardShortcuts library stores it in UserDefaults.
    #expect(Shortcut(keyboardShortcuts: #"{"carbonModifiers":256,"carbonKeyCode":49}"#)
        == Shortcut(keyCode: 49, carbonModifiers: 256))
    #expect(Shortcut(keyboardShortcuts: "not json") == nil)
}

@Test func readsMacOSsOwnShortcutsOnlyWhileTheyAreOn() {
    // com.apple.symbolichotkeys: [character, key code, Cocoa modifier flags].
    let inputSource: [String: Any] = ["enabled": true, "value": ["parameters": [32, 49, 262_144]]]
    let finderSearch: [String: Any] = ["enabled": 1, "value": ["parameters": [65535, 49, 1_572_864]]]
    let spotlightOff: [String: Any] = ["enabled": false, "value": ["parameters": [65535, 49, 1_048_576]]]
    #expect(Shortcut(symbolicHotKey: inputSource) == Shortcut(keyCode: 49, carbonModifiers: 4096))
    #expect(Shortcut(symbolicHotKey: finderSearch) == Shortcut(keyCode: 49, carbonModifiers: 2304))
    #expect(Shortcut(symbolicHotKey: spotlightOff) == nil)
}
