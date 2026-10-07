import CoreGraphics
import Testing
@testable import WingmanCore

// Trees below mirror what Slack 4.x exposed on 2026-09-27 (probe: role + DOM classes per node).

private func el(_ role: String, cls classes: [String] = [], title: String = "", value: String = "",
                desc: String = "", _ frame: CGRect, focused: Bool = false, handle: Int = -1,
                _ children: [UINode] = []) -> UINode {
    UINode(role: role, classes: classes, title: title, value: value, desc: desc, frame: frame,
           focused: focused, children: children, handle: handle)
}

private func header(_ name: String, x: CGFloat = 360) -> UINode {
    el("AXButton", cls: ["c-button-unstyled", "p-view_header__big_button", "p-view_header__big_button--channel"],
       title: name, CGRect(x: x + 40, y: 40, width: 90, height: 28))
}

/// The three nodes Slack emits for one message: sender button, timestamp link, rich-text body.
private func message(_ sender: String?, time: String = "", _ body: String, x: CGFloat = 400, y: CGFloat) -> [UINode] {
    var nodes: [UINode] = []
    if let sender {
        nodes.append(el("AXButton", cls: ["c-link--button", "c-message__sender_button"], title: sender,
                        CGRect(x: x, y: y, width: 60, height: 18)))
        nodes.append(el("AXLink", cls: ["c-link", "c-timestamp"], desc: time, CGRect(x: x + 70, y: y, width: 50, height: 18),
                        [el("AXStaticText", value: String(time.suffix(7)), CGRect(x: x + 70, y: y, width: 50, height: 18))]))
    }
    nodes.append(el("AXGroup", cls: ["p-rich_text_section"], CGRect(x: x, y: y + 20, width: 380, height: 20),
                    [el("AXStaticText", value: body, CGRect(x: x, y: y + 20, width: 380, height: 20))]))
    return nodes
}

private func composer(_ draft: String = "", x: CGFloat = 360, width: CGFloat = 420, focused: Bool = false,
                      handle: Int = 7) -> UINode {
    el("AXTextArea", cls: draft.isEmpty ? ["ql-editor", "ql-blank"] : ["ql-editor"], value: draft, desc: "傳送訊息到 #開發",
       CGRect(x: x, y: 780, width: width, height: 40), focused: focused, handle: handle)
}

private func window(_ children: [UINode], title: String = "開發 (頻道) - Moniit - Slack") -> UINode {
    el("AXWindow", title: title, CGRect(x: 0, y: 0, width: 800, height: 900),
       [el("AXWebArea", CGRect(x: 0, y: 0, width: 800, height: 900), children)])
}

@Test func channelMessagesCarrySenderTimeTextAndWhoIsMe() {
    let tree = window([header("#開發")]
        + message("Mia", time: "9月25日 晚上9:03:12", "Android 那個跳頁的 bug 修好了嗎？", y: 200)
        + message("Leo", time: "9月25日 晚上9:05:40", "修好了，在跑測試", y: 260)
        + [composer()])

    let convo = SlackParser.parse(window: tree, myName: "Leo")

    #expect(convo == Conversation(
        title: "#開發", isThread: false,
        messages: [
            ChatMessage(sender: "Mia", time: "9月25日 晚上9:03:12", text: "Android 那個跳頁的 bug 修好了嗎？", isMe: false),
            ChatMessage(sender: "Leo", time: "9月25日 晚上9:05:40", text: "修好了，在跑測試", isMe: true),
        ],
        draft: "", composerHandle: 7, composerFrame: CGRect(x: 360, y: 780, width: 420, height: 40)))
}

@Test func bodyKeepsParagraphsMentionsAndFilesButDropsSlackChrome() {
    let r = { (y: CGFloat) in CGRect(x: 400, y: y, width: 300, height: 18) }
    let tabs = el("AXTabGroup", cls: ["draggable_tabs_container"], r(80), [
        el("AXRadioButton", cls: ["channel_tab"], title: "訊息", r(80), [el("AXStaticText", value: "訊息", r(80))])])
    let divider = el("AXPopUpButton", cls: ["c-message_list__day_divider__label__pill"], title: "跳至…", r(110),
                     [el("AXStaticText", value: "今天", r(110))])
    let body = [
        el("AXGroup", cls: ["p-rich_text_section"], r(160), [
            el("AXLink", cls: ["c-link", "c-member_slug"], title: "@Leo", r(160), [el("AXStaticText", value: "@Leo", r(160))]),
            el("AXStaticText", value: " 可以幫我看一下嗎", r(160))]),
        el("AXGroup", cls: ["p-rich_text_section"], r(180), [el("AXStaticText", value: "客戶很急", r(180))]),
        el("AXGroup", cls: ["c-message_kit__file"], r(200), [
            el("AXStaticText", value: "IMG_1234.png", r(200)),
            el("AXButton", cls: ["c-icon_button"], title: "切換檔案", r(200))]),
        el("AXGroup", cls: ["c-message_kit__reaction_bar", "c-reaction_bar"], title: "回應", r(220), [
            el("AXCheckBox", cls: ["c-reaction"], title: "2 人以 舉雙手 回應", r(220), [el("AXStaticText", value: "2", r(220))])]),
        el("AXButton", cls: ["c-message__reply_count"], title: "5 則回覆", r(240)),
        el("AXGroup", cls: ["c-message__reply_bar_description"], r(240), [el("AXStaticText", value: "檢視對話串", r(240))]),
        el("AXGroup", cls: ["c-message_actions__container"], r(150), [
            el("AXButton", cls: ["c-icon_button"], title: "在對話串中回覆", r(150), [el("AXStaticText", value: "回覆", r(150))])]),
    ]
    let tree = window([header("#開發"), tabs, divider]
        + message("Mia", time: "今天 上午10:00", "", y: 130).dropLast() + body + [composer()])

    let convo = SlackParser.parse(window: tree, myName: "Leo")

    #expect(convo?.messages == [
        ChatMessage(sender: "Mia", time: "今天 上午10:00", text: "@Leo 可以幫我看一下嗎\n客戶很急\n[檔案] IMG_1234.png"),
    ])
}

@Test func readsOnlyThePaneWhoseComposerIsInUse() {
    func tree(channelFocused: Bool, threadFocused: Bool) -> UINode {
        let alsoSend = el("AXCheckBox", cls: ["c-input_checkbox"], title: "也傳送到 #開發",
                          CGRect(x: 590, y: 830, width: 16, height: 16))
        return window([header("#開發", x: 200)]
            + message("Mia", time: "上午9:00", "早安", x: 240, y: 200)
            + [composer(x: 200, width: 360, focused: channelFocused, handle: 1)]
            + message("Mia", time: "上午9:10", "這個 PR 可以今天合嗎？", x: 600, y: 200)
            + message("Leo", time: "上午9:12", "我看一下", x: 600, y: 260)
            + message("Mia", time: "上午9:30", "有結果了嗎", x: 600, y: 320)
            + [el("AXTextArea", cls: ["ql-editor", "ql-blank"], desc: "回覆…",
                  CGRect(x: 580, y: 780, width: 210, height: 40), focused: threadFocused, handle: 2), alsoSend])
    }

    let thread = SlackParser.parse(window: tree(channelFocused: false, threadFocused: true), myName: "Leo")
    #expect(thread?.isThread == true)
    #expect(thread?.composerHandle == 2)
    #expect(thread?.messages.map(\.text) == ["這個 PR 可以今天合嗎？", "我看一下", "有結果了嗎"])
    #expect(thread?.awaitingReply == true)

    let channel = SlackParser.parse(window: tree(channelFocused: true, threadFocused: false), myName: "Leo")
    #expect(channel?.isThread == false)
    #expect(channel?.composerHandle == 1)
    #expect(channel?.messages.map(\.text) == ["早安"])

    let unfocused = SlackParser.parse(window: tree(channelFocused: false, threadFocused: false), myName: "Leo")
    #expect(unfocused?.composerHandle == 2)
}

// Slack 4.x on 2026-10-07: the header button carries only a description, plus the visible name as a child in a DM.
private func liveHeader(desc: String, shown: String? = nil) -> UINode {
    el("AXButton", cls: ["c-button-unstyled", "p-view_header__big_button"], desc: desc,
       CGRect(x: 400, y: 40, width: 120, height: 28),
       shown.map { [el("AXStaticText", value: $0, CGRect(x: 420, y: 44, width: 80, height: 20))] } ?? [])
}

@Test func aChannelIsNamedByItsHashtagNotTheButtonsDescription() {
    let tree = window([liveHeader(desc: "#開發 的頻道詳細資料")] + message("Mia", "在嗎", y: 200) + [composer()])
    #expect(SlackParser.parse(window: tree, myName: "Leo")?.title == "#開發")
}

@Test func aDirectMessageIsNamedByTheNameItShows() {
    let tree = window([liveHeader(desc: "Yii Chen 的對話詳細資料", shown: "Yii Chen")] + message("Yii Chen", "在嗎", y: 200)
        + [composer()])
    #expect(SlackParser.parse(window: tree, myName: "Leo")?.title == "Yii Chen")
}
