import CryptoKit
import Foundation

/// How a remembered chat is kept on disk when "記住聊天紀錄" is on: sealed with AES-GCM under a key that
/// lives only in this Mac's Keychain, in a file whose name is a hash, so neither the words nor the chat's
/// name can be read from the file, a backup or a copy of it.
public enum HistoryCodec {
    private struct Line: Codable {
        var s: String?
        var t: String
        var m: Bool
    }

    public static func newKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func seal(_ messages: [ChatMessage], key: Data) throws -> Data {
        let plain = try JSONEncoder().encode(messages.map { Line(s: $0.sender, t: $0.text, m: $0.isMe) })
        guard let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: key)).combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return sealed
    }

    /// nil when the key is not the one it was sealed with, or the file is damaged.
    public static func open(_ data: Data, key: Data) -> [ChatMessage]? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key)),
              let lines = try? JSONDecoder().decode([Line].self, from: plain) else { return nil }
        return lines.map { ChatMessage(sender: $0.s, text: $0.t, isMe: $0.m) }
    }

    /// The chat's app and name, hashed.
    public static func fileName(for chat: String) -> String {
        SHA256.hash(data: Data(chat.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() + ".sealed"
    }
}
