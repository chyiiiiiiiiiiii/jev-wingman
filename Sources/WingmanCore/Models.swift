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

    /// What drafts are written for: this chat (and, in a thread, its first message, since Slack titles a thread with its
    /// channel), the message being answered, my own last message, and whether a reply is still owed. A re-read that
    /// differs only in spacing, in older messages or in a sender header (OCR reads lines a little differently each
    /// time, Slack drops a header as it scrolls) keeps the key, and with it the drafts. The same words sent again keep
    /// it too: the drafts for them still answer them.
    public var replyKey: String {
        let replyTo = replyRun.last.map { Transcript.words($0.text) } ?? ""
        let mine = messages.last(where: \.isMe).map { Transcript.words($0.text) } ?? ""
        let root = isThread ? messages.first.map { Transcript.words($0.text) } ?? "" : ""
        return [Transcript.words(title), isThread ? "t" : "c", root, replyTo, mine, awaitingReply ? "waiting" : "answered"]
            .joined(separator: "\u{1f}")
    }

    /// Their last message and the ones the same person sent just before it, oldest first, at most five. A message
    /// without a sender belongs to whoever spoke above it: Slack shows a sender once per run, and OCR reads none, so
    /// there every message since my last one is theirs.
    var replyRun: [ChatMessage] {
        guard var index = messages.lastIndex(where: { !$0.isMe }) else { return [] }
        func owner(_ i: Int) -> String? { messages[...i].last { $0.sender != nil }?.sender }
        let who = owner(index)
        var run = [messages[index]]
        while index > 0, run.count < 5 {
            index -= 1
            guard !messages[index].isMe, owner(index) == who else { break }
            run.insert(messages[index], at: 0)
        }
        return run
    }

    /// The message to answer as Jev reads it: `replyRun` as one text, since a thought often spans several messages and
    /// its question is not always the last.
    public var replyToText: String? {
        let run = replyRun
        return run.isEmpty ? nil : run.map(\.text).joined(separator: "\n")
    }

    /// The other side spoke last, so there is something to answer.
    public var awaitingReply: Bool {
        guard let last = messages.last else { return false }
        return !last.isMe
    }
}
