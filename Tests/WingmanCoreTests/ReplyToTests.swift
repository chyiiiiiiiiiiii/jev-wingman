import Testing
@testable import WingmanCore

private func m(_ text: String, _ sender: String? = "Mia", me: Bool = false) -> ChatMessage {
    ChatMessage(sender: me ? "我" : sender, text: text, isMe: me)
}

private func chat(_ messages: [ChatMessage]) -> Conversation {
    Conversation(title: "Mia", isThread: false, messages: messages, draft: "", composerHandle: -1, composerFrame: .zero)
}

@Test func aThoughtSentInSeveralMessagesIsReadWhole() {
    // Slack shows the sender once per run, so the later messages of a run come without one.
    let convo = chat([m("嗨"), m("嗨", me: true), m("明天的會可以改到下午嗎？"), m("我早上要去看醫生", nil)])
    #expect(convo.replyToText == "明天的會可以改到下午嗎？\n我早上要去看醫生")
}

@Test func someoneElsesMessageEndsTheRun() {
    #expect(chat([m("我也要去", "Leo"), m("幾點？")]).replyToText == "幾點？")
}

@Test func aRunIsAtMostFiveMessages() {
    let convo = chat((1...7).map { m("第\($0)則") })
    #expect(convo.replyToText == "第3則\n第4則\n第5則\n第6則\n第7則")
}

@Test func withNothingFromThemThereIsNothingToAnswer() {
    #expect(chat([m("在嗎", me: true)]).replyToText == nil)
}

@Test func aMessageWithoutASenderBelongsToWhoeverSpokeBeforeIt() {
    // In Slack the line without a sender is Leo's, the rest of his run, not Mia's.
    #expect(chat([m("我也要去", "Leo"), m("順便帶午餐", nil), m("幾點？")]).replyToText == "幾點？")
}
