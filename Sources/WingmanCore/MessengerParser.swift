import CoreGraphics

/// Turns Messenger (web, read through Chrome's accessibility tree) into the conversation on screen.
///
/// Messenger's class names are generated (`x1n2onr6`) and change between deployments, so nothing here
/// depends on them: the message box is found by where it sits, the conversation's column by the controls on
/// the message box's row, whose bubble is whose by which edge of that column it hugs.
public enum MessengerParser {
    static let controls: Set<String> = ["AXButton", "AXPopUpButton", "AXTextArea"]
    /// Text inside these is a control's label, not something a person wrote.
    static let labelled: Set<String> = ["AXButton", "AXPopUpButton", "AXLink", "AXHeading"]

    public static func parse(window: UINode) -> Conversation? {
        var nodes: [(node: UINode, inLabel: Bool)] = []
        func collect(_ node: UINode, _ inLabel: Bool) {
            nodes.append((node, inLabel))
            node.children.forEach { collect($0, inLabel || labelled.contains(node.role)) }
        }
        collect(window, false)

        // The message box is the text area low in the window. Its label changes wording (撰寫內容…,
        // not 撰寫訊息) and language, so place decides; the reader has already checked it is Messenger.
        let boxes = nodes.map(\.node).filter {
            $0.role == "AXTextArea" && $0.frame.midY > window.frame.minY + window.frame.height * 0.6
        }
        guard let composer = boxes.first(where: \.focused) ?? boxes.max(by: { $0.frame.midY < $1.frame.midY })
        else { return nil }

        // The conversation column spans the controls beside the message box (voice, attach … send).
        let reach = window.frame.width * 0.15
        let row = nodes.map(\.node).filter {
            controls.contains($0.role) && $0.frame.height < 80 && abs($0.frame.midY - composer.frame.midY) < 30
        }
        let left = row.filter { $0.frame.maxX <= composer.frame.minX + 1 && composer.frame.minX - $0.frame.minX <= reach }
            .map(\.frame.minX).min() ?? composer.frame.minX
        let right = row.filter { $0.frame.minX >= composer.frame.maxX - 1 && $0.frame.maxX - composer.frame.maxX <= reach }
            .map(\.frame.maxX).max() ?? composer.frame.maxX

        let heading = nodes.map(\.node)
            .filter { $0.role == "AXHeading" && !$0.text.isEmpty && $0.frame.minX >= left - 4 && $0.frame.maxX <= right + 4
                && $0.frame.maxY < composer.frame.minY }
            .min { $0.frame.minY < $1.frame.minY }
        let top = (heading?.frame.maxY ?? window.frame.minY + window.frame.height * 0.08) + 8
        let pane = CGRect(x: left, y: top, width: right - left, height: max(0, composer.frame.minY - 4 - top))

        let lines = nodes.compactMap { entry -> OCRLine? in
            let node = entry.node
            let text = node.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard node.role == "AXStaticText", !entry.inLabel, !text.isEmpty,
                  pane.insetBy(dx: -2, dy: -2).contains(node.frame) else { return nil }
            return OCRLine(text: text, frame: node.frame)
        }
        return Conversation(title: heading?.text ?? window.title, isThread: false,
                            messages: BubbleParser.messages(from: lines, pane: pane),
                            draft: composer.value.trimmingCharacters(in: .whitespacesAndNewlines),
                            composerHandle: composer.handle, composerFrame: composer.frame)
    }
}
