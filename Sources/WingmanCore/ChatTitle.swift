/// Whether the chat on screen is still the one a draft was written for.
public enum ChatTitle {
    /// `tolerant` is for titles read by OCR (Telegram), which can differ by a misread character; it only
    /// applies to titles long enough that one character cannot turn one person into another.
    public static func same(_ a: String, _ b: String, tolerant: Bool) -> Bool {
        let x = Array(a.filter { !$0.isWhitespace }.lowercased()), y = Array(b.filter { !$0.isWhitespace }.lowercased())
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x == y { return true }
        return tolerant && min(x.count, y.count) >= 8 && distance(x, y) <= 1
    }

    /// Levenshtein distance.
    static func distance(_ x: [Character], _ y: [Character]) -> Int {
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var row = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(1, y.count) where j <= y.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return previous[y.count]
    }
}
