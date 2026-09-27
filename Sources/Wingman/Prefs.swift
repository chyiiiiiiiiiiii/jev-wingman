import Foundation
import Security

/// Keys live in the Keychain; everything else in UserDefaults. Environment variables win,
/// which keeps a developer's shell keys out of the Keychain entirely.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    /// Off for `--render`: an unsigned debug build reading the Keychain waits on a permission prompt.
    nonisolated(unsafe) static var usesKeychain = true
    static let defaultModel = "deepseek/deepseek-v4.1-flash"

    /// Picked by scripts/bench-writers.py on 2026-09-27: speed, cost, Taiwan wording, and whether
    /// the drafts invent times and facts the thread never gave.
    static let writerModels: [(id: String, label: String)] = [
        ("deepseek/deepseek-v4.1-flash", L("DeepSeek V4.1 Flash：最快、台灣用語最道地（推薦）")),
        ("google/gemini-3.1-flash-lite", L("Gemini 3.1 Flash-Lite：快，偶爾用「數據」這類大陸用語")),
        ("anthropic/claude-haiku-4.5", L("Claude Haiku 4.5：穩，但貴約 10 倍")),
    ]

    @Published var openRouterKey: String { didSet { Keychain.set(openRouterKey, account: "openrouter") } }
    @Published var typesafeKey: String { didSet { Keychain.set(typesafeKey, account: "typesafe") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    @Published var myName: String { didSet { UserDefaults.standard.set(myName, forKey: "myName") } }
    @Published var paused: Bool { didSet { UserDefaults.standard.set(paused, forKey: "paused") } }
    /// Set when the first-run steps are finished; people who set Wingman up before they existed count.
    var onboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarded") || (hasWriterKey && !myName.isEmpty) }
        set { UserDefaults.standard.set(newValue, forKey: "onboarded") }
    }
    @Published var hotkey: HotkeySetting {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(hotkey), forKey: "hotkey") }
    }

    static var storedMyName: String? {
        UserDefaults.standard.string(forKey: "myName").flatMap { $0.isEmpty ? nil : $0 }
    }

    private init() {
        let env = ProcessInfo.processInfo.environment
        openRouterKey = env["OPENROUTER_API_KEY"] ?? (Self.usesKeychain ? Keychain.get(account: "openrouter") : nil) ?? ""
        typesafeKey = env["TYPESAFE_API_KEY"] ?? (Self.usesKeychain ? Keychain.get(account: "typesafe") : nil) ?? ""
        model = UserDefaults.standard.string(forKey: "model") ?? Self.defaultModel
        myName = UserDefaults.standard.string(forKey: "myName") ?? ""
        paused = UserDefaults.standard.bool(forKey: "paused")
        hotkey = UserDefaults.standard.data(forKey: "hotkey")
            .flatMap { try? JSONDecoder().decode(HotkeySetting.self, from: $0) } ?? .standard
    }

    var hasWriterKey: Bool { !openRouterKey.isEmpty }

    /// Why a pasted value is not an API key, or nil when it looks like one. Keys have no spaces;
    /// pasting a whole command or sentence is the usual mistake.
    static func keyProblem(_ value: String, prefix: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(where: \.isWhitespace) { return L("這不像 key：中間有空白，可能貼到整段指令或文字了") }
        if !trimmed.hasPrefix(prefix) { return L("這不像 key：應該以 %@ 開頭", "\(prefix)") }
        return nil
    }
}

enum Keychain {
    private static let service = "com.moniit.wingman"

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
