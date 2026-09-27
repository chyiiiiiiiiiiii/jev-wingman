/// Builds messages from a stream of sender, time and text events, in reading order.
struct MessageReader {
    /// The user's names, lowercased; one app may show "Yii" where another shows "Yii Chen".
    let myNames: Set<String>
    var messages: [ChatMessage] = []
    var current: ChatMessage?
    private var lastSender: (name: String, isMe: Bool)?

    /// `myName` may list several names separated by commas.
    init(myName: String?) {
        myNames = Set((myName ?? "").split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }

    mutating func start(sender: String) {
        flush()
        let isMe = myNames.contains(sender.trimmingCharacters(in: .whitespaces).lowercased())
        current = ChatMessage(sender: sender, text: "", isMe: isMe)
        lastSender = (sender, isMe)
    }

    /// A new message from whoever spoke last, for apps that omit the header on consecutive messages.
    mutating func continueLastSender() {
        flush()
        current = ChatMessage(sender: lastSender?.name, text: "", isMe: lastSender?.isMe ?? false)
    }

    mutating func time(_ time: String) {
        current?.time = time
    }

    mutating func append(_ text: String) {
        if current == nil { current = ChatMessage(sender: nil, text: "") }
        current?.text += text
    }

    mutating func paragraph() {
        guard let text = current?.text, !text.isEmpty, !text.hasSuffix("\n") else { return }
        current?.text += "\n"
    }

    mutating func finish() -> [ChatMessage] {
        flush()
        return messages
    }

    private mutating func flush() {
        guard var message = current else { return }
        message.text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.text.isEmpty { messages.append(message) }
        current = nil
    }
}
