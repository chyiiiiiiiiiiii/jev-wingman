import Testing
@testable import WingmanCore

private func m(_ text: String, me: Bool = false, sender: String? = "Mia") -> ChatMessage {
    ChatMessage(sender: me ? "我" : sender, text: text, isMe: me)
}

private func chat(_ messages: [ChatMessage], title: String = "Mia") -> Conversation {
    Conversation(title: title, isThread: false, messages: messages, draft: "", composerHandle: -1, composerFrame: .zero)
}

@Test func rereadingAChatWithDifferentSpacingKeepsItsDrafts() {
    // OCR reads the same line with a space more or less from one capture to the next.
    #expect(chat([m("早安"), m("今天 開會嗎？")]).replyKey == chat([m("早安"), m("今天開會嗎？")]).replyKey)
    #expect(chat([m("在嗎")], title: "王 小明").replyKey == chat([m("在嗎")], title: "王小明").replyKey)
}

@Test func olderMessagesReadDifferentlyKeepTheDrafts() {
    // A misread older line, or a sender header Slack drops as it scrolls, is not a new conversation.
    #expect(chat([m("早女"), m("好", me: true), m("今天開會嗎？")]).replyKey
        == chat([m("早安"), m("好", me: true), m("今天開會嗎？")]).replyKey)
    #expect(chat([m("今天開會嗎？", sender: nil)]).replyKey == chat([m("今天開會嗎？")]).replyKey)
}

@Test func aNewMessageFromThemNeedsNewDrafts() {
    #expect(chat([m("今天開會嗎？")]).replyKey != chat([m("今天開會嗎？"), m("還是改明天？")]).replyKey)
}

@Test func myReplyEndsTheWait() {
    #expect(chat([m("今天開會嗎？")]).replyKey != chat([m("今天開會嗎？"), m("開", me: true)]).replyKey)
}

@Test func anotherChatIsAnotherKey() {
    #expect(chat([m("在嗎")], title: "Mia").replyKey != chat([m("在嗎")], title: "Leo").replyKey)
}

@Test func aNewMessageArrivesEvenWhenTheLastOneIsReadDifferently() {
    let before = [m("早"), m("今天 開會嗎？")]
    #expect(Arrivals.new(since: before, in: [m("早"), m("今天開會嗎？"), m("那三點見")]) == [m("那三點見")])
    #expect(Arrivals.new(since: before, in: [m("早"), m("今天 開會嗎？", sender: nil), m("那三點見")]) == [m("那三點見")])
}
