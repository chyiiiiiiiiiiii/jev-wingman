/// A chat as seen so far this session: what is on screen now, joined to what was on screen before.
///
/// Apps keep only the messages near the view in their tree, and LINE and Telegram show only what fits the
/// window. Joining each read to the last one lets Wingman remember messages scrolled past while it runs,
/// in memory only. Two reads join only where at least two messages in a row match, so repeated short
/// messages ("好", "ok") never glue unrelated stretches together; anything that does not line up starts over.
/// Messages match on who sent them and their words, not on details a view changes: Slack drops a message's
/// sender and time once its header scrolls away, and OCR can read a line with a space more or less.
public enum Transcript {
    public static func merge(known: [ChatMessage], seen: [ChatMessage], limit: Int = 60) -> [ChatMessage] {
        guard !known.isEmpty else { return Array(seen.suffix(limit)) }
        guard !seen.isEmpty else { return Array(known.suffix(limit)) }
        let merged: [ChatMessage]
        if contains(known, seen) {
            merged = known
        } else if let overlap = overlap(of: known, then: seen) {
            // New messages after what was known.
            merged = known.dropLast(overlap) + fuller(known.suffix(overlap), seen.prefix(overlap)) + seen.dropFirst(overlap)
        } else if let overlap = overlap(of: seen, then: known) {
            // Older messages scrolled into view.
            merged = seen.dropLast(overlap) + fuller(seen.suffix(overlap), known.prefix(overlap)) + known.dropFirst(overlap)
        } else {
            merged = seen
        }
        return Array(merged.suffix(limit))
    }

    /// The longest run, at least two long, that ends `first` and begins `second`.
    static func overlap(of first: [ChatMessage], then second: [ChatMessage]) -> Int? {
        let longest = min(first.count, second.count)
        guard longest >= 2 else { return nil }
        for length in stride(from: longest, through: 2, by: -1) where matches(first.suffix(length), second.prefix(length)) {
            return length
        }
        return nil
    }

    static func contains(_ whole: [ChatMessage], _ part: [ChatMessage]) -> Bool {
        guard part.count >= 2, part.count <= whole.count else { return false }
        return (0...(whole.count - part.count)).contains { matches(whole[$0..<($0 + part.count)], part[...]) }
    }

    static func matches(_ one: ArraySlice<ChatMessage>, _ other: ArraySlice<ChatMessage>) -> Bool {
        one.count == other.count && zip(one, other).allSatisfy(same)
    }

    /// The same message read twice: same side, same words give or take spaces, and the same sender when
    /// both reads have one.
    static func same(_ one: ChatMessage, _ other: ChatMessage) -> Bool {
        func words(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        return one.isMe == other.isMe && words(one.text) == words(other.text)
            && (one.sender == nil || other.sender == nil || one.sender == other.sender)
    }

    /// Of two reads of the same messages, the copy that still has its sender and time.
    static func fuller(_ one: ArraySlice<ChatMessage>, _ other: ArraySlice<ChatMessage>) -> [ChatMessage] {
        zip(one, other).map { a, b in (a.sender == nil && b.sender != nil) || (a.time == nil && b.time != nil) ? b : a }
    }
}
