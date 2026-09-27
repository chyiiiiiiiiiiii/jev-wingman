import CoreGraphics

/// Turns a snapshot of Discord's accessibility tree into the conversation in the channel on screen.
///
/// Discord is Electron; its DOM classes carry build hashes (`username_c19a55`), so classes are matched
/// by prefix. A message item holds a header (username, timestamp) only when it starts a group;
/// replies carry a preview of the message they answer, which is not part of what was said.
public enum DiscordParser {
    static let skipped = ["repliedMessage_", "reactions_", "buttonContainer_", "hiddenVisually_", "divider_",
                          "embed", "threadMessageAccessory"]

    public static func parse(window: UINode, myName: String?) -> Conversation? {
        var composers: [UINode] = [], lists: [UINode] = []
        walk(window) { node in
            if node.role == "AXTextArea" && node.hasClass("slateTextArea_") { composers.append(node) }
            if node.role == "AXList" && node.hasClass("scrollerInner_") { lists.append(node) }
            return true
        }
        guard let composer = composers.first(where: \.focused) ?? composers.first,
              let list = lists.max(by: { overlap($0.frame, composer.frame) < overlap($1.frame, composer.frame) })
        else { return nil }

        var reader = MessageReader(myName: myName)
        func visit(_ node: UINode, inContent: Bool) {
            if skipped.contains(where: node.hasClass) { return }
            if node.hasClass("message__") {
                if !node.hasClass("groupStart_") { reader.continueLastSender() }
            } else if node.hasClass("username_") {
                reader.start(sender: node.text)
                return
            } else if node.hasClass("timestamp_") {
                reader.time(firstText(in: node))
                return
            } else if node.hasClass("visualMediaItemContainer_") {
                reader.paragraph()
                reader.append("[圖片]")
                return
            }
            let content = inContent || node.hasClass("messageContent_")
            if node.hasClass("messageContent_") { reader.paragraph() }
            if content && node.role == "AXStaticText" { reader.append(node.value) }
            node.children.forEach { visit($0, inContent: content) }
        }
        visit(list, inContent: false)

        return Conversation(title: list.text.isEmpty ? window.title : list.text, isThread: false,
                            messages: reader.finish(),
                            draft: composer.value.trimmingCharacters(in: .whitespacesAndNewlines),
                            composerHandle: composer.handle, composerFrame: composer.frame)
    }

    private static func walk(_ node: UINode, _ visit: (UINode) -> Bool) {
        guard visit(node) else { return }
        for child in node.children { walk(child, visit) }
    }

    private static func firstText(in node: UINode) -> String {
        if node.role == "AXStaticText" { return node.value }
        for child in node.children {
            let text = firstText(in: child)
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    }
}
