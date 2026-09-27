import CoreGraphics
import Testing
@testable import WingmanCore

// Replying under public posts. Layout from threads.com/@…/post/… and instagram.com/p/… in a 1512×827 pt
// window, 2026-09-27; words and names replaced, generated class names left out.
private func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 200, _ h: CGFloat = 18) -> UINode {
    UINode(role: "AXStaticText", value: value, frame: CGRect(x: x, y: y, width: w, height: h))
}
private func node(_ role: String, _ label: String = "", _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 30, _ h: CGFloat = 30,
                  focused: Bool = false, value: String = "", handle: Int = -1, _ children: [UINode] = []) -> UINode {
    UINode(role: role, value: value, desc: label, frame: CGRect(x: x, y: y, width: w, height: h), focused: focused,
           children: children, handle: handle)
}
private func group(_ children: [UINode]) -> UINode {
    UINode(role: "AXGroup", frame: children.map(\.frame).reduce(CGRect.null) { $0.union($1) }, children: children)
}
private func link(_ label: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 90) -> UINode {
    node("AXLink", label, x, y, w, 18, [text(label, x, y, w)])
}

private func threadsPost(focused: Bool) -> UINode {
    UINode(role: "AXWindow", title: "(3) Threads", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [group([
        node("AXButton", "返回", 454, 16),
        UINode(role: "AXHeading", title: "串文", frame: CGRect(x: 514, y: 22, width: 40, height: 20)),
        text("5,432 次瀏覽", 514, 50, 90),
        group([   // the post, with its reply box inside it
            group([node("AXButton", "annie.lin 的大頭貼照", 454, 99, 36, 36), link("annie.lin", 514, 104), link("3小時", 604, 104, 40)]),
            node("AXPopUpButton", "更多", 1028, 104),
            group([text("今天終於把 side project 上線了，謝謝", 454, 148, 320), link("@chen", 776, 148, 50),
                   text(" 幫了超多忙", 826, 148, 100)]),
            group([text("繼續加油", 454, 172, 80)]),
            node("AXButton", "Video player", 454, 265, 210, 250),
            node("AXButton", "讚 15", 454, 562, 50, 30, [text("15", 484, 568, 20)]),
            node("AXButton", "回覆 12", 514, 562, 50, 30, [text("12", 544, 568, 20)]),
            node("AXPopUpButton", "排序：熱門", 454, 620, 90, 24, [text("熱門", 484, 624, 30)]),
            node("AXImage", "我的大頭貼照", 454, 670, 36, 36),
            group([node("AXTextArea", "文字欄位空白。請輸入內容以撰寫新回覆。", 514, 678, 430, 22, focused: focused, handle: 20)]),
            node("AXButton", "附加影音內容", 952, 670),
        ]),
        group([   // the replies below it
            link("skyler.w", 499, 736), link("1小時", 575, 736, 40), text("很強欸", 499, 766, 60),
            node("AXButton", "回覆", 544, 794),
        ]),
    ])])
}

@Test func readsTheThreadsPostAReplyIsBeingWrittenTo() {
    let convo = PostParser.parse(window: threadsPost(focused: true))

    #expect(convo?.isPost == true)
    #expect(convo?.composerHandle == 20)
    #expect(convo?.messages == [
        ChatMessage(sender: "annie.lin", text: "今天終於把 side project 上線了，謝謝 @chen 幫了超多忙\n繼續加油"),
    ])
    #expect(convo?.title.hasPrefix("annie.lin") == true)
}

@Test func readsNothingUnlessAReplyBoxHasFocus() {
    // Reading a post, or scrolling past it, is not replying to it.
    #expect(PostParser.parse(window: threadsPost(focused: false)) == nil)
}

private func instagramPost(draft: String) -> UINode {
    UINode(role: "AXWindow", title: "Instagram", frame: CGRect(x: 0, y: 0, width: 1512, height: 827), children: [group([
        // Header: author, a collaborator, a place.
        node("AXLink", "yes.coffee的大頭貼照", 786, 48, 32, 32), link("yes.coffee", 816, 50), text(" ", 906, 50, 4), text("和", 922, 50, 14),
        link("elle.w", 938, 50, 60), link("台北市信義區", 816, 66, 120),
        node("AXPopUpButton", "更多選項", 1058, 56),
        group([   // caption, then comments
            node("AXLink", "yes.coffee的大頭貼照", 771, 104, 32, 32), link("yes.coffee", 816, 106),
            group([text("8分鐘", 922, 106, 40)]),
            text("新品上市：桂花拿鐵", 816, 132, 200), text("限量兩週，歡迎來喝", 816, 165, 150), text(" ", 966, 165, 4),
            link("#咖啡", 970, 165, 50),
            node("AXButton", "查看翻譯", 816, 240, 60, 18),
            node("AXLink", "mia.chen的大頭貼照", 771, 280, 32, 32), link("mia.chen", 816, 282),
            text("看起來好好喝！甜度可以調嗎？", 906, 282, 220), group([text("3分鐘", 816, 304, 40)]),
            node("AXButton", "回覆", 862, 304, 30, 18),
            node("AXLink", "leo_k的大頭貼照", 771, 340, 32, 32), link("leo_k", 816, 342), text("週末去", 906, 342, 60),
            group([text("1分鐘", 816, 364, 40)]),
        ]),
        node("AXButton", "讚", 771, 505), node("AXButton", "64", 801, 510, 20, 18), node("AXButton", "回應", 831, 505),
        link("7分鐘", 771, 545, 40),
        group([node("AXLink", "", 771, 580, 32, 32),
               group([node("AXPopUpButton", "表情符號", 1043, 585),
                      node("AXTextArea", "留言……", 816, 592, 220, 20, focused: true, value: draft, handle: 30)])]),
    ])])
}

@Test func aCommentGoesUnderTheInstagramPost() {
    let convo = PostParser.parse(window: instagramPost(draft: ""))

    #expect(convo?.messages == [ChatMessage(sender: "yes.coffee", text: "新品上市：桂花拿鐵\n限量兩週，歡迎來喝 #咖啡")])
    #expect(convo?.composerHandle == 30)
}

@Test func aReplyToACommentAnswersThatComment() {
    // Instagram's 回覆 puts "@name " in the box: the answer is to that comment, under the post.
    let convo = PostParser.parse(window: instagramPost(draft: "@mia.chen "))

    #expect(convo?.messages == [
        ChatMessage(sender: "yes.coffee", text: "新品上市：桂花拿鐵\n限量兩週，歡迎來喝 #咖啡"),
        ChatMessage(sender: "mia.chen", text: "看起來好好喝！甜度可以調嗎？"),
    ])
    #expect(convo?.draft == "@mia.chen")
}
