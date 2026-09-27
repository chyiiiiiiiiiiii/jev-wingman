import CoreGraphics
import Foundation

/// One line of text Vision found in a chat window, in window points with a top-left origin.
public struct OCRLine: Equatable {
    public var text: String
    public var confidence: Double
    public var frame: CGRect
    /// Saturation of the background just around the text: own bubbles are coloured (LINE green,
    /// Telegram blue), the other side's are grey.
    public var tint: Double

    public init(text: String, confidence: Double = 1, frame: CGRect, tint: Double = 0) {
        self.text = text
        self.confidence = confidence
        self.frame = frame
        self.tint = tint
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

    public static func messages(from lines: [OCRLine], pane: CGRect) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var previous: OCRLine?
        for line in lines.sorted(by: { $0.frame.minY < $1.frame.minY })
        where pane.intersects(line.frame) && !isNoise(line.text) {
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
