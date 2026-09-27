/// Builds messages from a stream of sender, time and text events, in reading order.
struct MessageReader {
    let myName: String?
    var messages: [ChatMessage] = []
    var current: ChatMessage?

    init(myName: String?) {
        self.myName = myName?.trimmingCharacters(in: .whitespaces).lowercased()
    }

    mutating func start(sender: String) {
        flush()
        let isMe = myName.map { $0 == sender.trimmingCharacters(in: .whitespaces).lowercased() } ?? false
        current = ChatMessage(sender: sender, text: "", isMe: isMe)
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
