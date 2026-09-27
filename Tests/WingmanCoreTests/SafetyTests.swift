import Testing
@testable import WingmanCore

private func m(_ text: String, me: Bool = false) -> ChatMessage { ChatMessage(sender: me ? "我" : "Alex", text: text, isMe: me) }

@Test func onlyMessagesAppendedAfterTheLastReadCountAsArrivals() {
    let before = [m("早"), m("今天開會嗎？"), m("好", me: true)]
    // A new message after the one we last saw.
    #expect(Arrivals.new(since: before, in: before + [m("那三點見")]) == [m("那三點見")])
    // Same screen again, or scrolled so older messages show: nothing new.
    #expect(Arrivals.new(since: before, in: before).isEmpty)
    #expect(Arrivals.new(since: before, in: [m("上週的事"), m("早"), m("今天開會嗎？")]).isEmpty)
    // First read of a chat (nothing to compare with) or a different chat: nothing new.
    #expect(Arrivals.new(since: [], in: before).isEmpty)
    #expect(Arrivals.new(since: before, in: [m("另一個群組的訊息")]).isEmpty)
    // Older messages scrolled off the top while a new one arrived.
    #expect(Arrivals.new(since: before, in: [m("今天開會嗎？"), m("好", me: true), m("收到")]) == [m("收到")])
}

@Test func draftsAreTypedWithoutAnythingThatCouldSendOrReorder() {
    #expect(Typeable.text("好\n我三點到\r\n等等見") == "好 我三點到 等等見")
    #expect(Typeable.text("a\tb") == "a b")
    #expect(Typeable.text("可以\u{3}") == "可以")                       // ETX, which AppKit treats as Enter
    #expect(Typeable.text("ok\u{202E}evil\u{202C}") == "okevil")        // right-to-left override
    #expect(Typeable.text("讚 👨‍👩‍👧 ❤️") == "讚 👨‍👩‍👧 ❤️")               // joiners and variation selectors stay
}
