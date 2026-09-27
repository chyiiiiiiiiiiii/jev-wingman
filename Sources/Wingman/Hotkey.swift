import AppKit
import Carbon.HIToolbox

/// The shortcut that opens the suggestion panel; Carbon modifier masks, stored as JSON in UserDefaults.
struct HotkeySetting: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int
    var label: String

    static let standard = HotkeySetting(keyCode: kVK_Space, modifiers: optionKey, label: "⌥Space")

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

/// A system hotkey through Carbon, which needs no extra permission.
final class Hotkey {
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
            DispatchQueue.main.async { Hotkey.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
