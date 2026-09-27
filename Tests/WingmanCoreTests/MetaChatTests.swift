import CoreGraphics
import Testing
@testable import WingmanCore

// Instagram's and Threads' messages, read through Chrome's accessibility tree the same way as Messenger.
// Geometry from instagram.com/direct and threads.com/messages in a 1512×827 pt window, 2026-09-27;
// words replaced, generated class names left out.
private func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 18) -> UINode {
    UINode(role: "AXStaticText", value: value, frame: CGRect(x: x, y: y, width: w, height: h))
}
private func control(_ role: String, _ label: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 30, _ h: CGFloat = 30,
                     handle: Int = -1, _ children: [UINode] = []) -> UINode {
    UINode(role: role, desc: label, frame: CGRect(x: x, y: y, width: w, height: h), children: children, handle: handle)
}
private func bubble(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 18) -> UINode {
    // Instagram labels each bubble with its text and hangs react / reply / more buttons beside it.
    UINode(role: "AXGroup", desc: value, frame: CGRect(x: x, y: y - 8, width: w + 24, height: h + 16), children: [
        text(value, x, y, w, h),
        control("AXPopUpButton", "對訊息按心情", x + w + 30, y, 24, 24, [control("AXImage", "對訊息按心情", x + w + 30, y, 24, 24)]),
        control("AXButton", "回覆訊息", x + w + 58, y, 24, 24, [control("AXImage", "回覆訊息", x + w + 58, y, 24, 24)]),
    ])
}

private let instagram = UINode(role: "AXWindow", title: "Instagram • 訊息", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [
    // Inbox column on the left.
    control("AXButton", "使用者大頭貼照 Mia", 76, 322, 400, 72, [text("Mia", 166, 330, 60), text("你: 好喔", 166, 352, 60)]),
    // Conversation header.
    control("AXLink", "開啟 Alex 的個人檔案", 484, 14, 40, 40),
    UINode(role: "AXHeading", title: "Alex", frame: CGRect(x: 544, y: 22, width: 40, height: 20),
           children: [text("Alex", 544, 20, 40)]),
    text("alex.chen", 544, 40, 90, 15),
    control("AXButton", "語音通話", 1376, 16), control("AXButton", "視訊通話", 1420, 16),
    // A date line the list has scrolled under its top edge: one point tall.
    text("下午 3:05", 973, 129, 55, 1),
    // A reel I shared: one large button.
    control("AXButton", "notes_from_alex", 1300, 74, 180, 100, [control("AXImage", "片段", 1315, 140, 20, 20)]),
    bubble("這個看起來很適合週末去", 920, 186, 523, 38),
    bubble("這個好", 535, 283, 75),
    UINode(role: "AXLink", desc: "已編輯", frame: CGRect(x: 529, y: 248, width: 40, height: 15),
           children: [text("已編輯", 529, 248, 40, 15)]),
    bubble("國外那間呢", 535, 321, 120),
    bubble("如果要訂位的話我可以先問", 920, 443, 552, 38),
    bubble("誰先到誰排隊", 1256, 501, 228),
    bubble("先讓我想想", 535, 687, 180),
    control("AXButton", "❤️", 529, 711, 24, 20),
    // Seen, under the last message, set smaller than the messages.
    text("4小時前", 1410, 731, 47, 15),
    text("已看過", 1458, 731, 26, 15),
    // Message box row.
    control("AXPopUpButton", "選擇表情符號", 500, 767),
    control("AXTextArea", "訊息", 544, 770, 830, 22, handle: 9),
    control("AXButton", "語音訊息", 1376, 767), control("AXButton", "新增相片或影片", 1414, 767),
    control("AXButton", "按讚", 1458, 767),
])

@Test func readsAnInstagramConversation() {
    let convo = MessengerParser.parse(window: instagram)

    #expect(convo?.title == "Alex")
    #expect(convo?.composerHandle == 9)
    #expect(convo?.messages.map(\.text) == ["📎", "這個看起來很適合週末去", "這個好", "國外那間呢", "如果要訂位的話我可以先問誰先到誰排隊", "先讓我想想"])
    #expect(convo?.messages.map(\.isMe) == [true, true, false, false, true, false])
    // “4小時前 · 已看過” is not something anyone wrote: the other side still spoke last.
    #expect(convo?.awaitingReply == true)
}

private let threads = UINode(role: "AXWindow", title: "(2) 訊息 • Threads", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [
    // Inbox column on the left.
    control("AXLink", "Threads alex.chen", 257, 174, 380, 70, [text("alex.chen", 333, 190, 90), text("你傳送了一則貼文", 333, 215, 120)]),
    // Conversation header: no heading element, the name is a link at the top of the column.
    control("AXLink", "Threads alex.chen", 680, 14, 300, 40, [
        control("AXImage", "Threads alex.chen", 680, 16, 36, 36),
        text("alex.chen", 726, 17, 90),
        text("3 小時前在線上", 726, 41, 110, 15),
    ]),
    control("AXPopUpButton", "", 1466, 25, 24, 24),
    // Older messages the list keeps above its top edge, zero points tall.
    text("你在嗎", 1435, 129, 48, 0),
    text("在啊", 724, 129, 45, 0),
    // What is on screen.
    text("下午 2:55", 1056, 180, 54, 16),
    text("雙橡園那邊怎麼樣", 724, 231, 180),
    text("下午 3:10", 1055, 280, 55, 15),
    // A post I shared: a link card, with the post's words inside it.
    control("AXLink", "alex.chen 的貼文 週末去哪裡好", 1134, 300, 350, 440, [
        control("AXImage", "alex.chen", 1149, 320, 24, 24),
        text("週末去哪裡好", 1149, 380, 300),
    ]),
    // Message box row.
    control("AXPopUpButton", "更多選項", 673, 769),
    control("AXPopUpButton", "新增媒體", 741, 776, 24, 24),
    control("AXTextArea", "", 771, 772, 715, 22, handle: 12),
])

@Test func aSharedPostTallerThanThePaneStillCounts() {
    // The newest post runs under the message box and a few points past the column's right edge.
    var window = threads
    window.children.removeAll { $0.desc.hasPrefix("alex.chen 的貼文") }
    window.children.insert(control("AXLink", "alex.chen 的貼文 早安", 1131, 300, 360, 517), at: window.children.count - 3)
    #expect(MessengerParser.parse(window: window)?.messages.last == ChatMessage(sender: nil, text: "📎", isMe: true))
}

@Test func readsAThreadsConversation() {
    let convo = MessengerParser.parse(window: threads)

    #expect(convo?.title == "alex.chen")
    #expect(convo?.composerHandle == 12)
    #expect(convo?.messages == [
        ChatMessage(sender: nil, text: "雙橡園那邊怎麼樣", isMe: false),
        ChatMessage(sender: nil, text: "📎", isMe: true),
    ])
    // I shared a post after their question, so nothing is waiting on me.
    #expect(convo?.awaitingReply == false)
}
