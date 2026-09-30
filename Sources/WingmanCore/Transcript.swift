/// A chat as seen so far this session: what is on screen now, joined to what was on screen before.
///
/// Apps keep only the messages near the view in their tree, and LINE and Telegram show only what fits the
/// window. Joining each read to the last one lets Wingman remember messages scrolled past while it runs,
/// in memory only. Two reads join only where at least two messages in a row match, so repeated short
/// messages ("好", "ok") never glue unrelated stretches together; anything that does not line up starts over.
public enum Transcript {
    public static func merge(known: [ChatMessage], seen: [ChatMessage], limit: Int = 60) -> [ChatMessage] {
        guard !known.isEmpty else { return Array(seen.suffix(limit)) }
        guard !seen.isEmpty else { return Array(known.suffix(limit)) }
        let merged: [ChatMessage]
        if contains(known, seen) {
            merged = known
        } else if let overlap = overlap(of: known, then: seen) {
            merged = known + seen.dropFirst(overlap)            // new messages after what was known
        } else if let overlap = overlap(of: seen, then: known) {
            merged = seen + known.dropFirst(overlap)            // older messages scrolled into view
        } else {
            merged = seen
        }
        return Array(merged.suffix(limit))
    }

    /// The longest run, at least two long, that ends `first` and begins `second`.
    static func overlap(of first: [ChatMessage], then second: [ChatMessage]) -> Int? {
        let longest = min(first.count, second.count)
        guard longest >= 2 else { return nil }
        for length in stride(from: longest, through: 2, by: -1)
        where Array(first.suffix(length)) == Array(second.prefix(length)) {
            return length
        }
        return nil
    }

    static func contains(_ whole: [ChatMessage], _ part: [ChatMessage]) -> Bool {
        guard part.count >= 2, part.count <= whole.count else { return false }
        return (0...(whole.count - part.count)).contains { Array(whole[$0..<($0 + part.count)]) == part }
    }
}
