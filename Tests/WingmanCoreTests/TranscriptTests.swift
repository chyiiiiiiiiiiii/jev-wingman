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
