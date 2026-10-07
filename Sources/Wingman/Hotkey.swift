import AppKit
import Carbon.HIToolbox
import WingmanCore

/// The shortcut that opens the suggestion panel; Carbon modifier masks, stored as JSON in UserDefaults.
struct HotkeySetting: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int
    var label: String

    static let standard = HotkeySetting(keyCode: kVK_Space, modifiers: optionKey, label: "⌥Space")

    /// Tried in order on first launch when another app already answers ⌥Space.
    static let alternatives = [
        HotkeySetting(keyCode: kVK_Space, modifiers: optionKey | shiftKey, label: "⌥⇧Space"),
        HotkeySetting(keyCode: kVK_Space, modifiers: controlKey | shiftKey, label: "⌃⇧Space"),
        HotkeySetting(keyCode: kVK_Space, modifiers: cmdKey | shiftKey, label: "⇧⌘Space"),
    ]

    var shortcut: Shortcut { Shortcut(keyCode: keyCode, carbonModifiers: modifiers) }

    /// Who else answers this combination, by name; nil when nobody Wingman knows of does.
    var owner: String? { Clashes.owners().first { $0.shortcut == shortcut }?.name }

    /// From a key press in the recorder; nil without ⌘, ⌥ or ⌃, which would steal plain typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var modifiers = 0, symbols = ""
        if flags.contains(.control) { modifiers |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; symbols += "⌘" }
        let names = [kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc"]
        let key = names[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers, label: symbols + key)
    }

    init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }
}

/// Shortcuts other software answers. Carbon lets two apps register the same combination without a word, and the
/// press then goes to whichever registered first, so these are read from the owners' own settings instead.
enum Clashes {
    static func owners() -> [(name: String, shortcut: Shortcut)] {
        var found: [(name: String, shortcut: Shortcut)] = []
        let names = [60: L("macOS 切換輸入法"), 61: L("macOS 切換輸入法"), 64: "Spotlight", 65: L("Finder 搜尋")]
        let symbolic = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        for (id, entry) in symbolic {
            if let entry = entry as? [String: Any], let shortcut = Shortcut(symbolicHotKey: entry) {
                found.append((names[Int(id) ?? 0] ?? "macOS", shortcut))
            }
        }
        if running("com.raycast.macos"),
           let shortcut = UserDefaults(suiteName: "com.raycast.macos")?.string(forKey: "raycastGlobalHotkey").flatMap(Shortcut.init(raycast:)) {
            found.append(("Raycast", shortcut))
        }
        if running("com.openai.chat") {
            // ChatGPT's launcher is ⌥Space until someone changes it; a cleared shortcut is stored as something else.
            let stored = UserDefaults(suiteName: "com.openai.chat")?.object(forKey: "KeyboardShortcuts_toggleLauncher")
            if let shortcut = stored == nil ? Shortcut(keyCode: kVK_Space, carbonModifiers: optionKey)
                : (stored as? String).flatMap(Shortcut.init(keyboardShortcuts:)) {
                found.append(("ChatGPT", shortcut))
            }
        }
        return found
    }

    /// Only a running app holds its shortcut; whichever registered first gets the press.
    private static func running(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// A system hotkey through Carbon, which needs no extra permission.
final class Hotkey {
    /// Posted on every press of a Wingman shortcut, so settings can show that the press arrived.
    static let pressed = Notification.Name("WingmanHotkeyPressed")
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?
    private let id: UInt32

    init?(keyCode: Int, modifiers: Int, id: UInt32, handler: @escaping () -> Void) {
        Self.installHandler()
        self.id = id
        let hotKeyID = EventHotKeyID(signature: OSType(0x574E_4D4E), id: id)   // 'WNMN'
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr
        else { return nil }
        Self.handlers[id] = handler
    }

    /// Whether another app already holds this combination (registering it again fails).
    static func isFree(_ setting: HotkeySetting) -> Bool {
        var ref: EventHotKeyRef?
        let probe = EventHotKeyID(signature: OSType(0x574E_4D50), id: 99)
        guard RegisterEventHotKey(UInt32(setting.keyCode), UInt32(setting.modifiers), probe, GetApplicationEventTarget(),
                                  0, &ref) == noErr else { return false }
        UnregisterEventHotKey(ref)
        return true
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Hotkey.pressed, object: nil)
                Hotkey.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
