/// What changed between two reads of the same chat.
public enum Arrivals {
    /// Messages that came in after `previous` was read: the old last message is still there and new ones
    /// follow it. Opening a chat, switching chats or scrolling back through history yields none, so
    /// automatic analysis never fires just because someone looked.
    public static func new(since previous: [ChatMessage], in current: [ChatMessage]) -> [ChatMessage] {
        // The end of the last read is found in this one by as many of its last messages as both have, up to three,
        // matched the way Transcript matches them (OCR spacing and a scrolled-away sender header do not count): one
        // alone would match an earlier copy of a "？" sent twice.
        for length in stride(from: min(3, previous.count), through: 1, by: -1) where current.count >= length {
            let tail = previous.suffix(length)
            if let start = (0...(current.count - length)).last(where: {
                zip(current[$0..<($0 + length)], tail).allSatisfy(Transcript.same)
            }) {
                return Array(current[(start + length)...])
            }
        }
        return []
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
