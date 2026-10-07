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

@Test func sendingAnotherMessageOfMyOwnNeedsNewDrafts() {
    // After a follow-up is sent, the follow-ups written before it are stale.
    #expect(chat([m("今天開會嗎？"), m("開", me: true)]).replyKey
        != chat([m("今天開會嗎？"), m("開", me: true), m("三點在大會議室", me: true)]).replyKey)
}

@Test func twoThreadsOfOneChannelAreTwoKeys() {
    // Slack titles a thread with its channel; the thread's first message tells two apart.
    func thread(_ messages: [ChatMessage]) -> Conversation {
        Conversation(title: "#dev", isThread: true, messages: messages, draft: "", composerHandle: -1, composerFrame: .zero)
    }
    #expect(thread([m("部署好了嗎", sender: "Leo"), m("thanks!")]).replyKey
        != thread([m("文件在哪", sender: "Ann"), m("thanks!")]).replyKey)
}

@Test func aRepeatedMessageStillArrives() {
    // "？" sent again: the newer copy is new, not the one read before.
    #expect(Arrivals.new(since: [m("好", me: true), m("？")], in: [m("好", me: true), m("？"), m("？", sender: nil)])
        == [m("？", sender: nil)])
}
