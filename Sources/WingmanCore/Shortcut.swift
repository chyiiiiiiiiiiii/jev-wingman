import Foundation

/// A key combination as Carbon registers it, read from wherever another app keeps its own.
///
/// Carbon lets two apps register the same hotkey and does not say so; the one that registered first gets the
/// press. Raycast, ChatGPT and macOS itself all like ⌥Space or ⌘Space, so Wingman reads their settings to tell
/// the user before a shortcut quietly opens something else.
public struct Shortcut: Equatable {
    public var keyCode: Int
    /// ⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096.
    public var carbonModifiers: Int

    public init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Raycast's `raycastGlobalHotkey`, such as "Option-49" or "Command-Shift-49".
    public init?(raycast value: String) {
        let parts = value.split(separator: "-")
        guard let last = parts.last, let keyCode = Int(last) else { return nil }
        let masks = ["Command": 256, "Shift": 512, "Option": 2048, "Control": 4096]
        self.init(keyCode: keyCode, carbonModifiers: parts.dropLast().reduce(0) { $0 | (masks[String($1)] ?? 0) })
    }

    /// A shortcut saved by the KeyboardShortcuts library (ChatGPT and many others): {"carbonKeyCode":…,"carbonModifiers":…}.
    public init?(keyboardShortcuts json: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let keyCode = object["carbonKeyCode"] as? Int, let modifiers = object["carbonModifiers"] as? Int
        else { return nil }
        self.init(keyCode: keyCode, carbonModifiers: modifiers)
    }

    /// One entry of macOS's `AppleSymbolicHotKeys`, nil while it is switched off. Its parameters are the character,
    /// the key code and Cocoa's modifier flags.
    public init?(symbolicHotKey entry: [String: Any]) {
        guard (entry["enabled"] as? Bool) == true || (entry["enabled"] as? Int) == 1,
              let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3
        else { return nil }
        let flags = parameters[2]
        let pairs = [(1 << 20, 256), (1 << 17, 512), (1 << 19, 2048), (1 << 18, 4096)]
        self.init(keyCode: parameters[1], carbonModifiers: pairs.reduce(0) { flags & $1.0 != 0 ? $0 | $1.1 : $0 })
    }
}
