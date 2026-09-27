import CoreGraphics

/// Turns Messenger, Instagram's messages and Threads' messages (web, read through Chrome's accessibility
/// tree) into the conversation on screen. The last two are Messenger underneath and share its layout.
///
/// Their class names are generated (`x1n2onr6`) and change between deployments, so nothing here depends
/// on them: the message box is found by where it sits, the conversation's column by the controls on the
/// message box's row, whose bubble is whose by which edge of that column it hugs.
public enum MessengerParser {
    static let controls: Set<String> = ["AXButton", "AXPopUpButton", "AXTextArea"]
    /// Text inside these is a control's label (or the message box's placeholder), not something a person wrote.
    static let labelled: Set<String> = ["AXButton", "AXPopUpButton", "AXLink", "AXHeading", "AXTextArea"]
    /// A photo, reel or shared post: no words of its own, but it is a turn in the conversation.
    static let attachmentRoles: Set<String> = ["AXButton", "AXLink", "AXImage"]
    static let attachment = BubbleParser.attachment

    /// The text lines and column the last parse used, for `--dump` diagnostics.
    nonisolated(unsafe) public private(set) static var lastLines: [OCRLine] = []
    nonisolated(unsafe) public private(set) static var lastPane: CGRect = .zero

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

        func inColumn(_ frame: CGRect) -> Bool { frame.minX >= left - 4 && frame.maxX <= right + 4 }
        let heading = nodes.map(\.node)
            .filter { $0.role == "AXHeading" && !$0.text.isEmpty && inColumn($0.frame) && $0.frame.maxY < composer.frame.minY }
            .min { $0.frame.minY < $1.frame.minY }
        let top = (heading?.frame.maxY ?? window.frame.minY + window.frame.height * 0.08) + 8
        let pane = CGRect(x: left, y: top, width: right - left, height: max(0, composer.frame.minY - 4 - top))
        // Threads has no heading: the name is the first text at the top of the column.
        let name = heading?.text ?? nodes.map(\.node)
            .filter { $0.role == "AXStaticText" && !$0.value.isEmpty && $0.frame.height >= 4 && inColumn($0.frame)
                && $0.frame.maxY <= top }
            .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }?.value

        // The placeholder (撰寫內容給…) is its own node floating just above the box: drop text that
        // repeats the box's label, and anything on the box's row.
        let boxLabel = [composer.desc, composer.title].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lines = nodes.compactMap { entry -> OCRLine? in
            let node = entry.node
            let text = node.value.trimmingCharacters(in: .whitespacesAndNewlines)
            // A line the list has scrolled under its edge is still in the tree, a point tall or less.
            guard node.role == "AXStaticText", !entry.inLabel, !text.isEmpty, node.frame.height >= 4,
                  pane.insetBy(dx: -2, dy: -2).contains(node.frame),
                  !boxLabel.contains(where: { $0 == text || $0.hasPrefix(text) }),
                  node.frame.maxY < composer.frame.minY - 6 else { return nil }
            return OCRLine(text: text, frame: node.frame)
        }
        let turns = trimmingStatus(lines + attachments(in: window, pane: pane), pane: pane)
        lastLines = turns
        lastPane = pane
        return Conversation(title: name ?? window.title, isThread: false,
                            messages: BubbleParser.messages(from: turns, pane: pane),
                            draft: composer.value.trimmingCharacters(in: .whitespacesAndNewlines),
                            composerHandle: composer.handle, composerFrame: composer.frame)
    }

    /// Photos, reels and shared posts in the pane, the outermost element of each, as one 📎 line at the part
    /// that shows (a tall post runs past the pane's edges). Avatars, reaction buttons and emoji are smaller.
    static func attachments(in window: UINode, pane: CGRect) -> [OCRLine] {
        var found: [OCRLine] = []
        func visit(_ node: UINode) {
            let shown = node.frame.intersection(pane)
            if attachmentRoles.contains(node.role), !shown.isNull, shown.width >= 56, shown.height >= 56,
               node.frame.midX > pane.minX, node.frame.midX < pane.maxX {
                found.append(OCRLine(text: attachment, frame: shown))
                return
            }
            node.children.forEach(visit)
        }
        visit(window)
        return found
    }

    /// Instagram prints “4小時前 · 已看過” (Seen 4h ago) under the last message, in smaller type than any
    /// message; left in, it would read as a message of mine. Lines below everything else that are set
    /// smaller than the smallest message go. A short message under long ones is half their height or
    /// less, so it stays.
    static func trimmingStatus(_ lines: [OCRLine], pane: CGRect) -> [OCRLine] {
        var ordered = lines.sorted { $0.frame.minY < $1.frame.minY }
        while let last = ordered.last, last.text != attachment {
            // Measured against the messages above the line's row: “4小時前” and “已看過” are two nodes side by side.
            let body = ordered.dropLast()
                .filter { $0.frame.maxY <= last.frame.midY && $0.text != attachment && !BubbleParser.isNoise($0.text)
                    && BubbleParser.side(of: $0, in: pane) != nil }
                .map(\.frame.height).min()
            guard let body, last.frame.height < body * 0.92, last.frame.height >= body * 0.6 else { break }
            ordered.removeLast()
        }
        return ordered
    }
}
