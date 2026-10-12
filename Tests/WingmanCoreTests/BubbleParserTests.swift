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

// Geometry and colours from Vision on a real Telegram window without bubbles (night theme, 626 pt wide)
// on 2026-10-12; the words and names are replaced. Everyone's text starts at the same left edge; a
// coloured name heads each run, times sit at the right edge, and "✓✓" before a time reads as "W".
private func telegramList(myCheck: String = "W ") -> [OCRLine] {
    func at(_ text: String, y: CGFloat, x: CGFloat, to maxX: CGFloat, h: CGFloat = 14, ink: Double = 0) -> OCRLine {
        OCRLine(text: text, frame: CGRect(x: x, y: y, width: maxX - x, height: h), ink: ink)
    }
    return [
        at("Bring your own cup!", y: 56, x: 52, to: 113, h: 12),              // a link preview, indented
        at("DevFest", y: 195, x: 87, to: 318, h: 52),                          // words in a picture
        at("2026", y: 273, x: 235, to: 282, h: 17, ink: 0.44),
        at("8:52 PM", y: 392, x: 584, to: 625, h: 12, ink: 0.17),
        at("Yii Chen", y: 393, x: 52, to: 104, h: 12, ink: 0.75),             // a quoted message
        at("請問活動要怎麼報名？", y: 407, x: 52, to: 442, h: 16),
        at("這次是邀請制，今年沒有公開徵稿，如果你願意來講，", y: 437, x: 44, to: 540, h: 13),
        at("再告訴我題目和長度", y: 453, x: 44, to: 542, h: 15),
        at("謝謝！", y: 468, x: 45, to: 120, h: 16),
        at("Yii Chen", y: 530, x: 44, to: 96, h: 13, ink: 0.75),
        at("\(myCheck)9:14 PM", y: 530, x: 567, to: 625, h: 13, ink: 0.31),
        at("好，我準備一下！", y: 546, x: 45, to: 197, h: 17),
        at("9:15 PM", y: 579, x: 586, to: 625, h: 11, ink: 0.17),
        at("Kai Lin", y: 581, x: 43, to: 99, h: 12, ink: 0.60),
        at("太好了，謝謝！", y: 595, x: 44, to: 197, h: 15),
    ]
}

@Test func readsTelegramWithoutBubblesByTheColouredNamesAndSkipsTimesQuotesAndPictures() {
    let pane = CGRect(x: 0, y: 56, width: 626, height: 613)
    let expected = [
        ChatMessage(sender: nil, text: "這次是邀請制，今年沒有公開徵稿，如果你願意來講，再告訴我題目和長度謝謝！", isMe: false),
        ChatMessage(sender: "Yii Chen", text: "好，我準備一下！", isMe: true),
        ChatMessage(sender: "Kai Lin", text: "太好了，謝謝！", isMe: false),
    ]
    // "Yii" in settings is a first name of "Yii Chen".
    #expect(BubbleParser.messages(from: telegramList(myCheck: ""), pane: pane, myName: "Yii") == expected)
    // Without a name, the read ticks before my message's time tell.
    #expect(BubbleParser.messages(from: telegramList(), pane: pane, myName: nil) == expected)
}

@Test func aGroupWithBubblesStillTellsMineBySideThoughTheirBubblesCarryColouredNames() {
    let pane = CGRect(x: 0, y: 0, width: 626, height: 600)
    let lines = [
        OCRLine(text: "Kai Lin", frame: CGRect(x: 60, y: 100, width: 50, height: 12), ink: 0.6),
        OCRLine(text: "明天幾點集合？", frame: CGRect(x: 60, y: 116, width: 120, height: 15)),
        OCRLine(text: "九點，車站見", frame: CGRect(x: 480, y: 200, width: 100, height: 15), tint: 0.5),
    ]
    #expect(BubbleParser.messages(from: lines, pane: pane, myName: "Yii") == [
        ChatMessage(sender: nil, text: "Kai Lin明天幾點集合？", isMe: false),
        ChatMessage(sender: nil, text: "九點，車站見", isMe: true),
    ])
}
