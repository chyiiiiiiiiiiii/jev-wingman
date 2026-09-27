import CoreGraphics
import Foundation

/// The public post (Threads, Instagram) a reply is being written under, read through Chrome's accessibility tree.
///
/// Only a reply box that has focus is read, and only what sits above it in its own post: scrolling a feed or
/// reading a post reads nothing. From the box, the nearest enclosing element that holds a post is taken (the
/// post itself on a Threads post page, the caption-and-comments column on Instagram); in it, each username
/// link starts an author's block and the text after it is theirs. The first real block is the post. A box
/// that already starts with "@name" is answering that person's comment, which then comes last.
public enum PostParser {
    public static func parse(window: UINode) -> Conversation? {
        guard let chain = focusedReplyBox(in: window), let box = chain.last else { return nil }
        for container in chain.dropLast().reversed() {
            let blocks = blocks(in: container, above: box).filter { $0.text.count >= 2 }
            guard let post = blocks.first else { continue }
            let draft = box.value.trimmingCharacters(in: .whitespacesAndNewlines)
            var messages = [ChatMessage(sender: post.sender, text: String(post.text.prefix(1500)))]
            if let name = mentioned(in: draft),
               let comment = blocks.dropFirst().last(where: { $0.sender.caseInsensitiveCompare(name) == .orderedSame }) {
                messages.append(ChatMessage(sender: comment.sender, text: String(comment.text.prefix(500))))
            }
            return Conversation(title: "\(post.sender)：\(post.text.prefix(24))", isThread: false, messages: messages,
                                draft: draft, composerHandle: box.handle, composerFrame: box.frame, isPost: true)
        }
        return nil
    }

    /// The focused text area and the elements around it, outermost first.
    static func focusedReplyBox(in root: UINode) -> [UINode]? {
        if root.role == "AXTextArea" && root.focused { return [root] }
        for child in root.children {
            if let found = focusedReplyBox(in: child) { return [root] + found }
        }
        return nil
    }

    struct Block {
        var sender: String
        var text = ""
        var last: CGRect?
    }

    /// Authors and what they wrote, in reading order, above the reply box.
    static func blocks(in container: UINode, above box: UINode) -> [Block] {
        var blocks: [Block] = []
        func add(_ piece: String, _ frame: CGRect) {
            guard !blocks.isEmpty, frame.height >= 4, frame.maxY <= box.frame.minY + 2 else { return }
            var block = blocks[blocks.count - 1]
            if block.text.isEmpty {
                block.text = piece.trimmingCharacters(in: .whitespaces)
            } else if let last = block.last, abs(frame.midY - last.midY) < max(4, last.height / 2) {
                block.text += joiner(block.text, piece) + piece
            } else {
                block.text += "\n" + piece.trimmingCharacters(in: .whitespaces)
            }
            block.text = block.text.trimmingCharacters(in: .newlines)
            block.last = frame
            blocks[blocks.count - 1] = block
        }
        func visit(_ node: UINode) {
            if node.handle == box.handle && box.handle >= 0 { return }
            let label = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch node.role {
            case "AXHeading":
                // "No comments yet" and the like head their own block; nothing under it belongs to an author.
                if !blocks.isEmpty { blocks.append(Block(sender: "")) }
            case "AXLink":
                if isUsername(label), node.frame.maxY <= box.frame.minY + 2 {
                    blocks.append(Block(sender: label))
                } else if label.hasPrefix("#") || label.hasPrefix("@") {
                    add(label, node.frame)     // hashtags and mentions are part of what was written
                }
            case "AXButton", "AXPopUpButton", "AXTextArea", "AXTextField", "AXImage":
                break                          // controls and pictures: their labels are not anyone's words
            case "AXStaticText":
                if !isNoise(node.value) { add(node.value, node.frame) }
            default:
                node.children.forEach(visit)
            }
        }
        visit(container)
        return blocks.filter { !$0.sender.isEmpty }
    }

    /// Instagram and Threads usernames: letters, digits, dots and underscores, and not a time like "3h".
    static func isUsername(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9._]{2,30}$"#, options: .regularExpression) != nil
            && text.contains(where: \.isLetter) && !isNoise(text)
    }

    static func mentioned(in draft: String) -> String? {
        guard let match = draft.range(of: #"^@[A-Za-z0-9._]+"#, options: .regularExpression) else { return nil }
        return String(draft[match].dropFirst())
    }

    /// Times, counts and separators printed around posts and comments.
    static let noise = [
        #"^\s*$"#, #"^[•·・|]$"#,
        #"^\d[\d,.]*\s*(萬|千|K|M)?$"#,
        #"^\d+\s?(秒|分鐘|分|小時|時|天|日|週|周|星期|個月|月|年)前?$"#,
        #"^\d+\s?[smhdwy]$"#,
        #"^\d+\s?(sec|secs|min|mins|minutes?|hrs?|hours?|days?|wks?|weeks?|mo|months?|yrs?|years?)( ago)?$"#,
        #"^(剛剛|just now|now|已編輯|edited)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func isNoise(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..., in: text)
        return noise.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// Pieces on one line: keep their own spaces, add one before a hashtag or mention, and between words.
    static func joiner(_ before: String, _ piece: String) -> String {
        guard let end = before.last, let start = piece.first, !end.isWhitespace, !start.isWhitespace else { return "" }
        return start == "#" || start == "@" ? " " : BubbleParser.joiner(before, piece)
    }
}
