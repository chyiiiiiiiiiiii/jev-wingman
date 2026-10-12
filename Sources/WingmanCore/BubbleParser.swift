import CoreGraphics
import Foundation

/// One line of text Vision found in a chat window, in window points with a top-left origin.
public struct OCRLine: Equatable {
    public var text: String
    public var confidence: Double
    public var frame: CGRect
    /// Saturation just around the text, above the chat's own background: own bubbles are coloured
    /// (LINE green, Telegram blue), the other side's are grey.
    public var tint: Double
    /// Saturation of the text's own colour: Telegram without bubbles writes sender names in colour.
    public var ink: Double

    public init(text: String, confidence: Double = 1, frame: CGRect, tint: Double = 0, ink: Double = 0) {
        self.text = text
        self.confidence = confidence
        self.frame = frame
        self.tint = tint
        self.ink = ink
    }
}

/// Turns OCR lines from a bubble-style chat (LINE, Telegram) into messages.
public enum BubbleParser {
    /// Stands for a photo, reel or shared post: a turn of its own that never continues a bubble.
    public static let attachment = "📎"

    /// Timestamps and read receipts sit beside bubbles, not inside what anyone wrote.
    static let noise = [
        #"^(上午|下午|晚上|凌晨|中午|早上)?\s?\d{1,2}[:：]\d{2}(\s?[AaPp][Mm])?$"#,
        #"^已讀(\s?\d+)?$"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// A message's time at the right edge, in Telegram without bubbles: "✓✓" before it (read as "W", "VV"
    /// and the like) marks a message of mine, and "PM" is sometimes read as "PN".
    static let stamp = try! NSRegularExpression(
        pattern: #"^(?:([WVv√✓✔/]{1,2})\s?)?(?:edited\s?|已編輯\s?)?(?:上午|下午|晚上|凌晨|中午|早上)?\s?\d{1,2}[:：]\d{2}(?:\s?[AaPp][MmNn])?$"#)

    /// `myName` tells my run of messages in a layout without bubbles; bubbles are told apart by side.
    public static func messages(from lines: [OCRLine], pane: CGRect, myName: String? = nil) -> [ChatMessage] {
        let shown = lines.sorted(by: { $0.frame.minY < $1.frame.minY }).filter { pane.intersects($0.frame) }
        if let listed = listed(shown, pane: pane, myName: myName) { return listed }
        var messages: [ChatMessage] = []
        var previous: OCRLine?
        for line in shown where !isNoise(line.text) {
            guard let isMe = side(of: line, in: pane) else { continue }
            // A wrapped bubble's next line starts right under the last; separate bubbles leave a gap.
            if let last = messages.last, last.isMe == isMe, let previous,
               line.text != attachment, previous.text != attachment,
               line.frame.minY - previous.frame.maxY < previous.frame.height * 0.8 {
                messages[messages.count - 1].text += joiner(last.text, line.text) + line.text
            } else {
                messages.append(ChatMessage(sender: nil, text: line.text, isMe: isMe))
            }
            previous = line
        }
        return messages
    }

    /// Telegram without bubbles: everyone's text starts at one left edge, a coloured name heads each run of
    /// messages, and each message's time sits at the right edge of its first row. nil for any other layout,
    /// including one where a line sits on my side.
    static func listed(_ lines: [OCRLine], pane: CGRect, myName: String?) -> [ChatMessage]? {
        let times = lines.filter { $0.frame.minX > pane.midX && match(stamp, $0.text) != nil }
        let content = lines.filter { !times.contains($0) }
        // The edge is the leftmost one that two lines share, so a stray word cannot set it.
        let starts = content.map(\.frame.minX)
        guard let edge = starts.filter({ x in starts.filter { abs($0 - x) <= 2 }.count >= 2 }).min(),
              !content.contains(where: { side(of: $0, in: pane) == true }) else { return nil }
        // Quotes, link previews and words inside pictures are indented from that edge.
        let column = content.filter { abs($0.frame.minX - edge) <= 4 }
        let names = column.indices.filter { i in
            let line = column[i], text = line.text.lowercased()
            guard line.ink >= 0.4, line.text.count <= 40, !text.contains("://"), !text.contains("www."),
                  i + 1 < column.count else { return false }
            return column[i + 1].frame.minY - line.frame.maxY < line.frame.height * 1.5
        }
        guard !names.isEmpty else { return nil }
        let mine = MessageReader(myName: myName).myNames
        /// Read ticks on a time between the previous line and the end of this one.
        func ticked(after previous: OCRLine?, through line: OCRLine) -> Bool? {
            let time = times.first { $0.frame.midY > (previous?.frame.maxY ?? -.infinity) - 2 && $0.frame.midY <= line.frame.maxY }
            return time.map { match(stamp, $0.text)?.range(at: 1).location != NSNotFound }
        }

        var messages: [ChatMessage] = []
        var sender: (name: String, isMe: Bool)?
        var previous: OCRLine?
        var startsMessage = true
        for (i, line) in column.enumerated() {
            if names.contains(i) {
                let name = line.text.lowercased()
                let named = mine.contains(name) || mine.contains { name.hasPrefix($0 + " ") }
                sender = (line.text, named || ticked(after: previous, through: line) == true)
                startsMessage = true
            } else {
                let time = ticked(after: previous, through: line)
                if !startsMessage, time == nil, let previous, let last = messages.last,
                   line.frame.minY - previous.frame.maxY < previous.frame.height * 0.8 {
                    messages[messages.count - 1].text += joiner(last.text, line.text) + line.text
                } else {
                    messages.append(ChatMessage(sender: sender?.name, text: line.text,
                                                isMe: sender?.isMe == true || time == true))
                }
                startsMessage = false
            }
            previous = line
        }
        return messages
    }

    private static func match(_ pattern: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        let text = text.trimmingCharacters(in: .whitespaces)
        return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Latin words need a space where a line wrapped; Chinese does not.
    static func joiner(_ before: String, _ after: String) -> String {
        guard let end = before.last, let start = after.first else { return "" }
        return end.isASCII && start.isASCII && !end.isWhitespace ? " " : ""
    }

    /// true = mine, false = theirs, nil = cannot tell (centred or spanning the pane).
    static func side(of line: OCRLine, in pane: CGRect) -> Bool? {
        if line.tint >= 0.25 { return true }
        let left = line.frame.minX - pane.minX, right = pane.maxX - line.frame.maxX
        if right < left * 0.6 { return true }
        if left < right * 0.6 { return false }
        return nil
    }

    static func isNoise(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(text.startIndex..., in: text)
        return noise.contains { $0.firstMatch(in: text, range: range) != nil }
    }
}
