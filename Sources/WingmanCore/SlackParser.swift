import CoreGraphics

/// Turns a snapshot of Slack's accessibility tree into the conversation beside the composer.
///
/// Slack is Electron; once `AXManualAccessibility` is set, every node carries its DOM classes
/// (`AXDOMClassList`). A message is a flat run of nodes in reading order: a sender button,
/// a timestamp link, then rich-text sections. Consecutive messages from one person omit the
/// sender button, so their text folds into the previous message.
public enum SlackParser {
    /// Subtrees that sit among messages but are Slack's own UI, not anything a person wrote.
    static let chrome = [
        "p-view_header", "draggable_tabs", "channel_tab", "c-tabs",
        "c-message_list__day_divider", "c-message__reply_count", "c-message__reply_bar",
        "c-reaction", "c-message_kit__reaction_bar", "c-message_actions", "c-file__actions",
        "c-input_checkbox", "c-wysiwyg_container", "p-control_strip",
    ]
    static let paragraphs = ["p-rich_text_section", "p-rich_text_block", "p-rich_text_list", "p-rich_text_preformatted"]

    public static func parse(window: UINode, myName: String?) -> Conversation? {
        var composers: [UINode] = []
        walk(window) { node in
            if node.role == "AXTextArea" && node.hasClass("ql-editor") { composers.append(node) }
            return true
        }
        // Channel and thread each have a composer; the one in use decides which pane we read.
        guard let composer = composers.first(where: \.focused) ?? composers.max(by: { $0.frame.minX < $1.frame.minX })
        else { return nil }
        var isThread = false

        var title = window.title
        var reader = MessageReader(myName: myName)
        walk(window) { node in
            if node.hasClass("p-view_header__big_button") {
                title = node.text
                return false
            }
            if node.hasClass("c-input_checkbox") && isBelow(node.frame, composer.frame) {
                isThread = true    // only a thread composer offers "also send to #channel"
                return false
            }
            guard isInPane(node.frame, above: composer.frame) else { return true }
            if node.hasClass("c-message__sender_button") {
                reader.start(sender: node.text)
                return false
            }
            if node.hasClass("c-timestamp") {
                reader.time(node.text)
                return false
            }
            if chrome.contains(where: node.hasClass) { return false }
            if node.hasClass("c-message_kit__file") {
                reader.paragraph()
                reader.append("[檔案] " + firstText(in: node))
                return false
            }
            if paragraphs.contains(where: node.hasClass) { reader.paragraph() }
            if node.role == "AXStaticText" { reader.append(node.value) }
            return true
        }

        return Conversation(title: title, isThread: isThread, messages: reader.finish(),
                            draft: composer.value.trimmingCharacters(in: .whitespacesAndNewlines),
                            composerHandle: composer.handle, composerFrame: composer.frame)
    }

    /// Pre-order walk; `visit` returns false to skip the node's subtree.
    private static func walk(_ node: UINode, _ visit: (UINode) -> Bool) {
        guard visit(node) else { return }
        for child in node.children { walk(child, visit) }
    }

    private static func firstText(in node: UINode) -> String {
        var found = ""
        walk(node) { child in
            if found.isEmpty && child.role == "AXStaticText" { found = child.value }
            return found.isEmpty
        }
        return found
    }

    /// Same column as the composer (panes sit side by side) and above it.
    private static func isInPane(_ frame: CGRect, above composer: CGRect) -> Bool {
        frame.height > 1 && frame.maxY <= composer.minY
            && frame.minX >= composer.minX - 8 && frame.minX < composer.maxX
    }

    private static func isBelow(_ frame: CGRect, _ composer: CGRect) -> Bool {
        frame.minY >= composer.maxY - 1 && frame.minY <= composer.maxY + 60
            && frame.minX >= composer.minX - 8 && frame.minX < composer.maxX
    }
}
