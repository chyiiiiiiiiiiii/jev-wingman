import AppKit
import ApplicationServices
import WingmanCore

/// Puts a reply into Slack's composer by typing it, the way a person would, and never presses Enter.
enum Inserter {
    enum Outcome {
        case inserted, typed, copied(String)

        var message: String {
            switch self {
            case .inserted: L("已填入，檢查後按 Enter 送出")
            case .typed: L("已輸入，看一下再按 Enter 送出")
            case let .copied(reason): L("%@，已複製到剪貼簿", "\(reason)")
            }
        }
    }

    @MainActor
    static func insert(_ text: String, app: ChatApp, expectedTitle: String, pid: pid_t) async -> Outcome {
        // A newline, or ETX, would send the message; a reply is one paragraph anyway.
        let line = Typeable.text(text)
        NSRunningApplication(processIdentifier: pid)?.activate()
        try? await Task.sleep(for: .milliseconds(150))

        guard let reading = await Readers.read(app, pid: pid, myName: Prefs.storedMyName) else {
            return copy(line, L("找不到 %@ 的輸入框", "\(app.name)"))
        }
        guard ChatTitle.same(reading.conversation.title, expectedTitle, tolerant: app == .telegram) else {
            return copy(line, L("聊天室已經切換"))
        }
        guard let composer = reading.composer else {
            // Telegram exposes no input element, but its input box has focus whenever a chat is open.
            // Keystrokes go to whichever app is in front, so type only if that is still Telegram.
            guard Front.current?.pid == pid else { return copy(line, L("聊天室已經切換")) }
            type(line, pid: nil)
            return .typed
        }
        AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(for: .milliseconds(80))
        // Keystrokes go to whatever has focus: if that is not the message box (a search field, a message
        // being edited), type nothing.
        guard focused(composer, pid: pid) else { return copy(line, L("填入沒有成功")) }

        let before = value(of: composer)
        type(line, pid: pid)
        try? await Task.sleep(for: .milliseconds(250))
        let after = value(of: composer)
        if landed(line, in: after, before: before) { return .inserted }

        // Some builds drop events addressed to the process; the HID stream reaches the key window.
        // Retry only if the first attempt changed nothing, so a draft is never typed twice.
        if after == before, Front.current?.pid == pid, focused(composer, pid: pid) {
            type(line, pid: nil)
            try? await Task.sleep(for: .milliseconds(250))
            if landed(line, in: value(of: composer), before: before) { return .inserted }
        }
        Log.write("insert not verified")
        return copy(line, L("填入沒有成功"))
    }

    /// OCR can read a chat name slightly differently between two captures; the start is enough.
    private static func focused(_ element: AXUIElement, pid: pid_t) -> Bool {
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focused)
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        return CFEqual(focused, element)
    }

    private static func type(_ text: String, pid: pid_t?) {
        var chunk = ""
        func send() {
            let units = Array(chunk.utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
            }
            chunk = ""
            usleep(8000)
        }
        for character in text {
            chunk.append(character)
            if chunk.utf16.count >= 16 { send() }
        }
        if !chunk.isEmpty { send() }
    }

    private static func value(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return value as? String ?? ""
    }

    private static func landed(_ text: String, in after: String, before: String) -> Bool {
        let squash = { (s: String) in s.filter { !$0.isWhitespace } }
        return squash(after).contains(String(squash(text).prefix(12))) && after != before
    }

    private static func copy(_ text: String, _ reason: String) -> Outcome {
        // This Mac only (not Universal Clipboard), and marked so clipboard managers skip it.
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        board.setString(text, forType: .string)
        board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        return .copied(reason)
    }
}

enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Wingman.log")

    /// Events and timings only; message text never goes to the log.
    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
