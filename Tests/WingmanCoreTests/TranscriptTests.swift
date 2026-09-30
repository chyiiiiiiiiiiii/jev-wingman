import Testing
@testable import WingmanCore

private func m(_ text: String, me: Bool = false) -> ChatMessage { ChatMessage(sender: me ? "我" : "Mia", text: text, isMe: me) }
private let a = m("週五的會還開嗎"), b = m("開，改到下午三點", me: true), c = m("好，那我準備簡報"),
            d = m("記得帶上個月的數字", me: true), e = m("收到"), f = m("API 文件今天來得及更新嗎？")

@Test func newMessagesContinueWhatWasSeen() {
    #expect(Transcript.merge(known: [a, b, c, d], seen: [c, d, e]) == [a, b, c, d, e])
}

@Test func scrollingUpAddsTheOlderMessagesInFront() {
    #expect(Transcript.merge(known: [c, d, e], seen: [a, b, c, d]) == [a, b, c, d, e])
}

@Test func aWindowAlreadySeenChangesNothing() {
    #expect(Transcript.merge(known: [a, b, c, d, e, f], seen: [c, d]) == [a, b, c, d, e, f])
}

@Test func messagesThatDoNotLineUpStartOver() {
    // A different chat state (or OCR reading it differently) is not glued onto the old one.
    #expect(Transcript.merge(known: [a, b], seen: [e, f]) == [e, f])
}

@Test func oneMatchingMessageIsNotEnoughToJoin() {
    // Two separate "好" are not the same message.
    let ok = m("好")
    #expect(Transcript.merge(known: [a, ok], seen: [ok, f]) == [ok, f])
}

@Test func keepsOnlyTheNewestUpToTheLimit() {
    let many = (1...10).map { m("第 \($0) 則") }
    #expect(Transcript.merge(known: Array(many[0..<6]), seen: Array(many[4..<10]), limit: 8) == Array(many[2..<10]))
}

@Test func aMessageThatLostItsSenderHeaderIsStillTheSameMessage() {
    // Slack drops the sender and time from a message once its header scrolls out of view.
    let first = ChatMessage(sender: "Mia", time: "12:39", text: "週五的會還開嗎")
    let headless = ChatMessage(sender: nil, text: "週五的會還開嗎")
    let merged = Transcript.merge(known: [first, b, c], seen: [headless, b, c, d])
    #expect(merged.count == 4)
    #expect(merged.first?.sender == "Mia")      // the fuller copy is kept
    #expect(merged.last == d)
}

@Test func spacingDifferencesDoNotSplitAMessage() {
    // OCR can read the same line with a space more or less.
    let read1 = ChatMessage(sender: nil, text: "好，那我準備簡報"), read2 = ChatMessage(sender: nil, text: "好， 那我準備簡報")
    #expect(Transcript.merge(known: [a, read1, e], seen: [read2, e, f]).count == 4)
}
