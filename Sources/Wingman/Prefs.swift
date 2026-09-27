import Foundation
import Security

/// Keys live in the Keychain; everything else in UserDefaults. Environment variables win,
/// which keeps a developer's shell keys out of the Keychain entirely.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    static let defaultModel = "anthropic/claude-haiku-4.5"

    @Published var openRouterKey: String { didSet { Keychain.set(openRouterKey, account: "openrouter") } }
    @Published var typesafeKey: String { didSet { Keychain.set(typesafeKey, account: "typesafe") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    @Published var myName: String { didSet { UserDefaults.standard.set(myName, forKey: "myName") } }
    @Published var paused: Bool { didSet { UserDefaults.standard.set(paused, forKey: "paused") } }

    static var storedMyName: String? {
        UserDefaults.standard.string(forKey: "myName").flatMap { $0.isEmpty ? nil : $0 }
    }

    private init() {
        let env = ProcessInfo.processInfo.environment
        openRouterKey = env["OPENROUTER_API_KEY"] ?? Keychain.get(account: "openrouter") ?? ""
        typesafeKey = env["TYPESAFE_API_KEY"] ?? Keychain.get(account: "typesafe") ?? ""
        model = UserDefaults.standard.string(forKey: "model") ?? Self.defaultModel
        myName = UserDefaults.standard.string(forKey: "myName") ?? ""
        paused = UserDefaults.standard.bool(forKey: "paused")
    }

    var hasWriterKey: Bool { !openRouterKey.isEmpty }
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
