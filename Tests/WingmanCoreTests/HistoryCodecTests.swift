import Foundation
import Testing
@testable import WingmanCore

private let chat = [
    ChatMessage(sender: "Mia", text: "API 文件今天來得及更新嗎？"),
    ChatMessage(sender: "我", text: "來得及，下午補上", isMe: true),
]

@Test func sealedHistoryOpensWithItsKey() throws {
    let key = HistoryCodec.newKey()
    let sealed = try HistoryCodec.seal(chat, key: key)
    #expect(HistoryCodec.open(sealed, key: key) == chat)
}

@Test func anotherKeyCannotOpenIt() throws {
    let sealed = try HistoryCodec.seal(chat, key: HistoryCodec.newKey())
    #expect(HistoryCodec.open(sealed, key: HistoryCodec.newKey()) == nil)
}

@Test func nothingReadableIsWrittenToDisk() throws {
    let sealed = try HistoryCodec.seal(chat, key: HistoryCodec.newKey())
    let bytes = String(decoding: sealed, as: UTF8.self)
    #expect(!bytes.contains("API"))
    #expect(!bytes.contains("Mia"))
}

@Test func filesAreNamedWithoutTheChatsName() {
    let name = HistoryCodec.fileName(for: "slack|#dev")
    #expect(!name.contains("dev"))
    #expect(name == HistoryCodec.fileName(for: "slack|#dev"))
    #expect(name != HistoryCodec.fileName(for: "slack|#design"))
}
