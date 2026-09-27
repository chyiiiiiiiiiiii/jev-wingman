import CoreGraphics
import Testing
@testable import WingmanCore

// Geometry from Vision on a real LINE window (dark theme, 660×700 pt chat pane) on 2026-09-27;
// the words are replaced. Own bubbles are green, so their background tint is high.
private let pane = CGRect(x: 0, y: 0, width: 660, height: 700)

private func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, conf: Double = 1, tint: Double = 0.05) -> OCRLine {
    OCRLine(text: text, confidence: conf, frame: CGRect(x: x * 660, y: y * 700, width: w * 660, height: 17), tint: tint)
}

@Test func splitsLineBubblesIntoTheirsAndMineAndDropsTimesAndReadReceipts() {
    let lines = [
        line("我去過那家", x: 0.13, y: 0.40, w: 0.11),
        line("下午12:51", x: 0.88, y: 0.41, w: 0.09),
        line("已讀", x: 0.68, y: 0.47, w: 0.05),
        line("桌子看起來很好做", x: 0.75, y: 0.49, w: 0.17, tint: 0.62),
        line("已讀", x: 0.80, y: 0.54, w: 0.05),
        line("可以嗎", x: 0.88, y: 0.56, w: 0.05, tint: 0.62),
        line("下午1:12", x: 0.75, y: 0.57, w: 0.10),
        line("氣氛不錯", x: 0.13, y: 0.66, w: 0.11),
        line("而且人很多", x: 0.13, y: 0.73, w: 0.13),
        line("下午1:17", x: 0.30, y: 0.75, w: 0.10),
        line("好喔", x: 0.88, y: 0.83, w: 0.05, tint: 0.62),
        line("下次去", x: 0.85, y: 0.89, w: 0.08, tint: 0.62),
        line("下午1:25", x: 0.73, y: 0.91, w: 0.10),
    ]

    #expect(BubbleParser.messages(from: lines, pane: pane) == [
        ChatMessage(sender: nil, text: "我去過那家", isMe: false),
        ChatMessage(sender: nil, text: "桌子看起來很好做", isMe: true),
        ChatMessage(sender: nil, text: "可以嗎", isMe: true),
        ChatMessage(sender: nil, text: "氣氛不錯", isMe: false),
        ChatMessage(sender: nil, text: "而且人很多", isMe: false),
        ChatMessage(sender: nil, text: "好喔", isMe: true),
        ChatMessage(sender: nil, text: "下次去", isMe: true),
    ])
}

@Test func joinsWrappedLinesDropsCentredDividersAndReadsColouredWideBubblesAsMine() {
    let pane = CGRect(x: 0, y: 0, width: 850, height: 700)
    func at(_ text: String, x: CGFloat, w: CGFloat, y: CGFloat, tint: Double = 0.04) -> OCRLine {
        OCRLine(text: text, frame: CGRect(x: x * 850, y: y, width: w * 850, height: 17), tint: tint)
    }
    let lines = [
        at("Unread messages", x: 0.42, w: 0.16, y: 280),
        at("26 September", x: 0.43, w: 0.14, y: 320),
        at("這個連結好像打不開，", x: 0.06, w: 0.39, y: 350),
        at("可以再傳一次嗎", x: 0.06, w: 0.24, y: 371),
        at("12:45 AM", x: 0.90, w: 0.07, y: 372),
        at("Can you send", x: 0.06, w: 0.15, y: 420),
        at("the deck again?", x: 0.06, w: 0.17, y: 441),
        at("我等等再傳一次，順便把新的版本也附上", x: 0.35, w: 0.57, y: 490, tint: 0.5),
        at("好", x: 0.06, w: 0.03, y: 560),
    ]

    #expect(BubbleParser.messages(from: lines, pane: pane) == [
        ChatMessage(sender: nil, text: "這個連結好像打不開，可以再傳一次嗎", isMe: false),
        ChatMessage(sender: nil, text: "Can you send the deck again?", isMe: false),
        ChatMessage(sender: nil, text: "我等等再傳一次，順便把新的版本也附上", isMe: true),
        ChatMessage(sender: nil, text: "好", isMe: false),
    ])
}
