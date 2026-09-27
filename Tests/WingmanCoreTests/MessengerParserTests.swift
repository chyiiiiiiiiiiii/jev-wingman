import CoreGraphics
import Testing
@testable import WingmanCore

// Geometry from messenger.com in Chrome, 1512×827 pt window, 2026-09-27; words replaced. Messenger's
// class names are generated (x1n2onr6), so the fixture carries none and the parser must not need them.
private func at(_ role: String, _ text: String = "", x: CGFloat, y: CGFloat, w: CGFloat = 0.02, h: CGFloat = 20,
                desc: String = "", handle: Int = -1, _ children: [UINode] = []) -> UINode {
    UINode(role: role, value: role == "AXStaticText" ? text : "", desc: role == "AXStaticText" ? desc : (desc.isEmpty ? text : desc),
           frame: CGRect(x: x * 1512, y: y * 827, width: w * 1512, height: h), children: children, handle: handle)
}
private func bubble(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat) -> UINode {
    at("AXGroup", x: x, y: y, w: w, [at("AXStaticText", text, x: x, y: y, w: w)])
}

private let page = UINode(role: "AXWindow", title: "Messenger", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [
    // Chat list on the left and the info column on the right.
    at("AXLink", "Amy", x: 0.21, y: 0.29, w: 0.06, [at("AXStaticText", "12週", x: 0.21, y: 0.29)]),
    at("AXButton", "更多選項", x: 0.26, y: 0.92, w: 0.02),
    at("AXStaticText", "媒體和檔案", x: 0.80, y: 0.40, w: 0.08),
    // Conversation header.
    at("AXHeading", "Alex Chen", x: 0.33, y: 0.05, w: 0.06, [at("AXStaticText", "Alex Chen", x: 0.33, y: 0.05, w: 0.06)]),
    at("AXButton", "開始語音通話", x: 0.66, y: 0.04),
    // Messages: theirs hug the left edge, mine the right.
    bubble("morning 早安", x: 0.33, y: 0.12, w: 0.08),
    at("AXButton", "輸入表情符號回應", x: 0.73, y: 0.10, [at("AXStaticText", "輸入…", x: 0.74, y: 0.10)]),
    bubble("我知道了，晚點再跟你確認時間", x: 0.53, y: 0.22, w: 0.18),
    bubble("他們還沒回", x: 0.68, y: 0.27, w: 0.043),
    at("AXStaticText", "下午 2:13", x: 0.49, y: 0.31, w: 0.04),
    bubble("竟然這麼快", x: 0.33, y: 0.38, w: 0.05),
    bubble("Damn 哈哈", x: 0.33, y: 0.43, w: 0.05),
    at("AXButton", "1 個心情回應", x: 0.37, y: 0.45, [at("AXImage", "❤️", x: 0.37, y: 0.45)]),
    at("AXImage", "Link preview", x: 0.71, y: 0.55),
    bubble("他們今天都在", x: 0.67, y: 0.63, w: 0.05),
    bubble("不對，是明天才對", x: 0.33, y: 0.74, w: 0.08),
    // Composer row.
    at("AXButton", "傳送語音訊息", x: 0.29, y: 0.92),
    at("AXButton", "附加檔案", x: 0.32, y: 0.92),
    at("AXTextArea", x: 0.40, y: 0.93, w: 0.29, desc: "撰寫訊息", handle: 7),
    at("AXButton", "送出讚", x: 0.72, y: 0.92),
])

@Test func readsMessengerByGeometryAlone() {
    let convo = MessengerParser.parse(window: page)

    #expect(convo?.title == "Alex Chen")
    #expect(convo?.composerHandle == 7)
    #expect(convo?.messages == [
        ChatMessage(sender: nil, text: "morning 早安", isMe: false),
        ChatMessage(sender: nil, text: "我知道了，晚點再跟你確認時間", isMe: true),
        ChatMessage(sender: nil, text: "他們還沒回", isMe: true),
        ChatMessage(sender: nil, text: "竟然這麼快", isMe: false),
        ChatMessage(sender: nil, text: "Damn 哈哈", isMe: false),
        ChatMessage(sender: nil, text: "他們今天都在", isMe: true),
        ChatMessage(sender: nil, text: "不對，是明天才對", isMe: false),
    ])
    #expect(convo?.awaitingReply == true)
}

@Test func findsNothingOnAPageWithoutAMessageBox() {
    let github = UINode(role: "AXWindow", title: "GitHub", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [
        at("AXTextArea", x: 0.40, y: 0.30, w: 0.29, desc: "Leave a comment"),
    ])
    #expect(MessengerParser.parse(window: github) == nil)
}

@Test func findsTheMessageBoxByPlaceWhateverItsLabelSays() {
    // The real box is labelled 撰寫內容… (2026-09-27), not 撰寫訊息; the search box sits at the top.
    let window = UINode(role: "AXWindow", title: "Messenger", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [
        UINode(role: "AXComboBox", desc: "搜尋 Messenger", frame: CGRect(x: 200, y: 120, width: 380, height: 36)),
        UINode(role: "AXHeading", title: "Alex Chen", frame: CGRect(x: 500, y: 40, width: 90, height: 20)),
        UINode(role: "AXStaticText", value: "我剛確認過，是週五", frame: CGRect(x: 500, y: 600, width: 120, height: 20)),
        UINode(role: "AXButton", desc: "傳送語音訊息", frame: CGRect(x: 438, y: 760, width: 30, height: 30)),
        UINode(role: "AXTextArea", desc: "撰寫內容給 Alex Chen", frame: CGRect(x: 605, y: 762, width: 440, height: 30), handle: 4),
        UINode(role: "AXButton", desc: "送出讚", frame: CGRect(x: 1089, y: 760, width: 30, height: 30)),
    ])

    let convo = MessengerParser.parse(window: window)

    #expect(convo?.composerHandle == 4)
    #expect(convo?.messages == [ChatMessage(sender: nil, text: "我剛確認過，是週五", isMe: false)])
}
