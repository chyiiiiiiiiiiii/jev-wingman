/// What changed between two reads of the same chat.
public enum Arrivals {
    /// Messages that came in after `previous` was read: the old last message is still there and new ones
    /// follow it. Opening a chat, switching chats or scrolling back through history yields none, so
    /// automatic analysis never fires just because someone looked.
    public static func new(since previous: [ChatMessage], in current: [ChatMessage]) -> [ChatMessage] {
        // The old last message is found the way Transcript matches messages: OCR spacing and a sender header
        // scrolled away do not make it a different message.
        guard let last = previous.last, let index = current.lastIndex(where: { Transcript.same($0, last) }) else { return [] }
        return Array(current[(index + 1)...])
    }
}

/// Text that is safe to type into someone else's app.
public enum Typeable {
    /// A draft as keystrokes: line breaks and tabs become spaces (a newline would send the message),
    /// other control characters and bidirectional overrides are dropped, emoji joiners stay.
    public static func text(_ draft: String) -> String {
        var typed = String.UnicodeScalarView()
        for scalar in draft.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                // Breaks and tabs become one space; ETX (AppKit's Enter) and the rest become nothing.
                if [0x0A, 0x0D, 0x09, 0x2028, 0x2029].contains(scalar.value), typed.last != " " { typed.append(" ") }
            case .format:
                // Joiners hold emoji and some scripts together; overrides and the like go.
                if scalar.value == 0x200D || scalar.value == 0x200C { typed.append(scalar) }
            default:
                typed.append(scalar)
            }
        }
        return String(typed).trimmingCharacters(in: .whitespaces)
    }
}
