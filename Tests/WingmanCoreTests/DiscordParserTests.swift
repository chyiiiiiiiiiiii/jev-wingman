import CoreGraphics
import Testing
@testable import WingmanCore

// Mirrors Discord 0.0.412 on 2026-09-27 (probe: role + DOM classes; class suffixes are build hashes).
private func el(_ role: String, cls: [String] = [], title: String = "", value: String = "", desc: String = "",
                x: CGFloat = 300, y: CGFloat, w: CGFloat = 500, focused: Bool = false, handle: Int = -1,
                _ children: [UINode] = []) -> UINode {
    UINode(role: role, classes: cls, title: title, value: value, desc: desc,
           frame: CGRect(x: x, y: y, width: w, height: 18), focused: focused, children: children, handle: handle)
}
private func text(_ s: String, y: CGFloat, x: CGFloat = 300) -> UINode { el("AXStaticText", value: s, x: x, y: y, w: 200) }

private let hoverBar = el("AXGroup", cls: ["buttonContainer_c19a55"], y: 120, [
    el("AXButton", cls: ["hoverBarButton_f84418"], title: "回覆", y: 120),
    el("AXGroup", cls: ["hiddenVisually_b18fe2"], y: 120, [text("回覆", y: 120)]),
])

private let firstMessage = el("AXGroup", cls: ["messageListItem__5126c"], y: 100, [
    el("AXGroup", cls: ["message__5126c", "cozyMessage__5126c", "groupStart__5126c"], desc: "Sam …", y: 100),
    el("AXHeading", cls: ["header_c19a55"], y: 100, [
        el("AXButton", cls: ["username_c19a55", "usernameColorOnName_c19a55"], title: "Sam", y: 100),
        el("AXGroup", cls: ["timestamp_c19a55", "timestampInline_c19a55"], y: 100, [text("凌晨 1:23", y: 100)]),
    ]),
    el("AXGroup", cls: ["markup__75297", "messageContent_c19a55"], y: 120, [text("新的語音模型出來了，大家試了嗎？", y: 120)]),
    el("AXGroup", cls: ["visualMediaItemContainer_f4758a"], y: 140, [el("AXImage", title: "圖片", y: 140)]),
    el("AXGroup", cls: ["reactions__23977"], y: 300, [
        el("AXCheckBox", cls: ["reactionInner__23977"], title: "lol，2 個回應", y: 300, [text("2", y: 300)])]),
    el("AXGroup", cls: ["hiddenVisually_b18fe2"], y: 310, [text("加入回應", y: 310)]),
    hoverBar,
])

private let divider = el("AXSplitter", cls: ["divider__5126c", "hasContent__5126c"], title: "2026年9月27日", y: 330)

private let reply = el("AXGroup", cls: ["messageListItem__5126c"], y: 350, [
    el("AXGroup", cls: ["message__5126c", "cozyMessage__5126c", "groupStart__5126c"], y: 350),
    el("AXGroup", cls: ["repliedMessage_c19a55"], y: 350, [
        el("AXButton", cls: ["username_c19a55"], title: "@Sam", y: 350),
        el("AXGroup", cls: ["repliedTextContent_c19a55", "markup__75297", "messageContent_c19a55"], y: 350,
           [text("新的語音模型出來了，大家試了嗎？", y: 350)]),
    ]),
    el("AXHeading", cls: ["header_c19a55"], y: 370, [
        el("AXButton", cls: ["username_c19a55"], title: "Yii", y: 370),
        el("AXGroup", cls: ["timestamp_c19a55"], y: 370, [text("中午 12:05", y: 370)]),
    ]),
    el("AXGroup", cls: ["markup__75297", "messageContent_c19a55"], y: 390, [text("試了，STT 的部分很準", y: 390)]),
])

// Same author again: Discord drops the header.
private let followUp = el("AXGroup", cls: ["messageListItem__5126c"], y: 420, [
    el("AXGroup", cls: ["message__5126c", "cozyMessage__5126c"], y: 420),
    el("AXGroup", cls: ["markup__75297", "messageContent_c19a55"], y: 420, [text("但中英夾雜會卡", y: 420)]),
])

private func window(focusedComposer: Bool = false) -> UINode {
    el("AXWindow", title: "Discord", x: 0, y: 0, w: 1200, [
        el("AXGroup", cls: ["search_c322aa"], x: 1000, y: 40, w: 180, [
            el("AXTextArea", cls: ["editor__25bec"], desc: "搜尋 Flutter Taipei", x: 1000, y: 40, w: 180, handle: 3)]),
        el("AXList", cls: ["scrollerInner__36d07"], title: "💡｜閒聊", x: 300, y: 90, w: 700,
           [firstMessage, divider, reply, followUp]),
        el("AXTextArea", cls: ["markup__75297", "editor__1b31f", "slateTextArea_ec4baf"], value: "", desc: "傳訊息到 💡｜閒聊",
           x: 360, y: 800, w: 600, focused: focusedComposer, handle: 9),
        el("AXList", cls: ["members_c8ffbb"], title: "成員", x: 1000, y: 90, w: 200, [text("Sam", y: 150, x: 1040)]),
    ])
}

@Test func readsDiscordMessagesWithoutReplyPreviewsReactionsOrHiddenText() {
    let convo = DiscordParser.parse(window: window(), myName: "Yii Chen, Yii")

    #expect(convo?.title == "💡｜閒聊")
    #expect(convo?.composerHandle == 9)
    #expect(convo?.messages == [
        ChatMessage(sender: "Sam", time: "凌晨 1:23", text: "新的語音模型出來了，大家試了嗎？\n[圖片]", isMe: false),
        ChatMessage(sender: "Yii", time: "中午 12:05", text: "試了，STT 的部分很準", isMe: true),
        ChatMessage(sender: "Yii", time: nil, text: "但中英夾雜會卡", isMe: true),
    ])
    #expect(convo?.awaitingReply == false)
}
