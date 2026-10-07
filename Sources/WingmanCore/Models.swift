import CoreGraphics

/// One accessibility element, copied out of the live tree so parsing is a pure function.
public struct UINode: Equatable {
    public var role: String
    public var classes: [String]
    public var title: String
    public var value: String
    public var desc: String
    public var frame: CGRect
    public var focused: Bool
    public var children: [UINode]
    /// Index into the snapshot's table of live elements, so the app can act on this node later.
    public var handle: Int

    public init(role: String, classes: [String] = [], title: String = "", value: String = "",
                desc: String = "", frame: CGRect = .zero, focused: Bool = false,
                children: [UINode] = [], handle: Int = -1) {
        self.role = role
        self.classes = classes
        self.title = title
        self.value = value
        self.desc = desc
        self.frame = frame
        self.focused = focused
        self.children = children
        self.handle = handle
    }

    /// The most informative label: accessibility puts the same text in different fields per role.
    public var text: String {
        [title, value, desc].max { $0.count < $1.count } ?? ""
    }

    public func hasClass(_ prefix: String) -> Bool {
        classes.contains { $0.hasPrefix(prefix) }
    }
}

public struct ChatMessage: Equatable {
    /// nil when the sender's header is scrolled out of view.
    public var sender: String?
    public var time: String?
    public var text: String
    public var isMe: Bool

    public init(sender: String?, time: String? = nil, text: String, isMe: Bool = false) {
        self.sender = sender
        self.time = time
        self.text = text
        self.isMe = isMe
    }
}

public struct Conversation: Equatable {
    public var title: String
    public var isThread: Bool
    public var messages: [ChatMessage]
    public var draft: String
    public var composerHandle: Int
    public var composerFrame: CGRect
    /// A public post (Threads, Instagram) being replied to, rather than a private chat.
    public var isPost: Bool

    public init(title: String, isThread: Bool, messages: [ChatMessage], draft: String,
                composerHandle: Int, composerFrame: CGRect, isPost: Bool = false) {
        self.title = title
        self.isThread = isThread
        self.messages = messages
        self.draft = draft
        self.composerHandle = composerHandle
        self.composerFrame = composerFrame
        self.isPost = isPost
    }

    /// A photo, video, sticker or shared post is in the conversation (as 📎).
    public var hasAttachments: Bool { messages.contains { $0.text == BubbleParser.attachment } }

    /// What drafts are written for: this chat, the message being answered, and whether it still waits for an
    /// answer. A re-read that differs only in spacing, in older messages or in a sender header (OCR reads lines a
    /// little differently each time, Slack drops a header as it scrolls) keeps the key, and with it the drafts.
    public var replyKey: String {
        let replyTo = messages.last { !$0.isMe }.map { Transcript.words($0.text) } ?? ""
        return [Transcript.words(title), isThread ? "t" : "c", replyTo, awaitingReply ? "waiting" : "answered"]
            .joined(separator: "\u{1f}")
    }

    /// The message to answer as Jev reads it: their last message with the ones the same person sent just before it,
    /// since a thought often spans several messages and its question is not always the last. At most five; a
    /// message without a sender (Slack shows it once per run) belongs to the run around it.
    public var replyToText: String? {
        guard var index = messages.lastIndex(where: { !$0.isMe }) else { return nil }
        var run = [messages[index]], sender = messages[index].sender
        while index > 0, run.count < 5 {
            index -= 1
            let message = messages[index]
            guard !message.isMe, message.sender == nil || sender == nil || message.sender == sender else { break }
            sender = sender ?? message.sender
            run.insert(message, at: 0)
        }
        return run.map(\.text).joined(separator: "\n")
    }

    /// The other side spoke last, so there is something to answer.
    public var awaitingReply: Bool {
        guard let last = messages.last else { return false }
        return !last.isMe
    }
}
