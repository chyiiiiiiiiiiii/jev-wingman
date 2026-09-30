import Foundation
import WingmanCore

/// "記住聊天紀錄": each chat's recent messages kept on this Mac between launches, off unless chosen.
///
/// Files are sealed with a key that only this Mac's Keychain holds (never synced, never in a backup), named by
/// a hash of the chat, left out of Time Machine, capped at 300 messages a chat, and dropped after 90 days
/// untouched. Turning the setting off, or erasing everything, deletes them all.
enum ChatHistory {
    static let limit = 300
    private static let keyAccount = "history"

    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.moniit.wingman/History", isDirectory: true)

    static func load(_ chat: String) -> [ChatMessage] {
        guard let key = key(creating: false),
              let data = try? Data(contentsOf: folder.appendingPathComponent(HistoryCodec.fileName(for: chat)))
        else { return [] }
        return HistoryCodec.open(data, key: key) ?? []
    }

    static func save(_ chat: String, _ messages: [ChatMessage]) {
        guard let key = key(creating: true), let sealed = try? HistoryCodec.seal(Array(messages.suffix(limit)), key: key)
        else { return }
        prepareFolder()
        try? sealed.write(to: folder.appendingPathComponent(HistoryCodec.fileName(for: chat)),
                          options: [.atomic, .completeFileProtection])
    }

    /// How many chats are remembered, for settings.
    static var count: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasSuffix(".sealed") }.count ?? 0
    }

    /// Chats nobody has opened for 90 days are forgotten.
    static func forgetStale() {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where ((try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) < cutoff {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Every remembered chat and the key that sealed them.
    static func eraseAll() {
        try? FileManager.default.removeItem(at: folder)
        Keychain.set("", account: keyAccount)
    }

    private static func key(creating: Bool) -> Data? {
        if let stored = Keychain.get(account: keyAccount), let key = Data(base64Encoded: stored) { return key }
        guard creating else { return nil }
        let key = HistoryCodec.newKey()
        Keychain.set(key.base64EncodedString(), account: keyAccount)
        return key
    }

    private static func prepareFolder() {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var folderURL = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folderURL.setResourceValues(values)
    }
}
