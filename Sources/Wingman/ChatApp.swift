import AppKit
import ApplicationServices
import WingmanCore

/// A chat app Wingman can read, and how it talks.
enum ChatApp: String, CaseIterable {
    case slack, discord, line, telegram, messenger

    var name: String {
        switch self {
        case .slack: "Slack"
        case .discord: "Discord"
        case .line: "LINE"
        case .telegram: "Telegram"
        case .messenger: "Messenger"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .discord: ["com.hnc.Discord"]
        case .line: ["jp.naver.line.mac"]
        case .telegram: ["ru.keepcoder.Telegram", "org.telegram.desktop"]
        // Messenger's web app, in Chromium browsers (they share Chrome's accessibility tree).
        case .messenger: ["com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser"]
        }
    }

    /// LINE and Telegram draw their messages without exposing text, so they are read from pixels.
    var readsPixels: Bool { self == .line || self == .telegram }

    /// A browser hosts other pages too: read it, and take the shortcut, only on a Messenger tab.
    var isBrowser: Bool { self == .messenger }

    /// Electron apps build their accessibility tree only when asked (AXManualAccessibility).
    var isElectron: Bool { self == .slack || self == .discord }

    /// Reading pixels costs a capture and, when the chat changed, an OCR pass.
    var pollInterval: TimeInterval { readsPixels ? 1.2 : isBrowser ? 1.0 : 0.7 }

    /// How replies should sound in this app, for the writer's rules.
    var register: String {
        switch self {
        case .slack: "這是工作用的 Slack：語氣像真人同事，自然、簡潔、有禮，不要客服腔，不要過度客套或堆砌表情符號。"
        case .discord: "這是 Discord 社群頻道：語氣輕鬆自然，像社群裡的成員在聊天，簡短，不要客服腔，也不要過度熱情或堆砌表情符號。"
        case .line, .telegram, .messenger: "這是日常通訊軟體：語氣像平常傳訊息，自然口語、簡短，可以用常見的語助詞，但不要裝熟、不要過度可愛或堆砌表情符號。"
        }
    }

    static func matching(_ running: NSRunningApplication?) -> ChatApp? {
        guard let id = running?.bundleIdentifier else { return nil }
        return allCases.first { $0.bundleIDs.contains(id) }
    }

    static var frontmost: (app: ChatApp, pid: pid_t)? {
        let running = NSWorkspace.shared.frontmostApplication
        return matching(running).map { ($0, running!.processIdentifier) }
    }
}

/// A conversation read from screen, plus the input element to type into when the app exposes one.
struct Reading {
    var conversation: Conversation
    var composer: AXUIElement?
}

enum Readers {
    static func read(_ app: ChatApp, pid: pid_t, myName: String?) async -> Reading? {
        switch app {
        case .slack:
            guard let (convo, snapshot) = Slack.read(pid: pid, myName: myName) else { return nil }
            return Reading(conversation: convo, composer: snapshot.elements[convo.composerHandle])
        case .discord:
            for window in AXSnapshot.windows(pid: pid) {
                let snapshot = AXSnapshot(window: window)
                if let convo = DiscordParser.parse(window: snapshot.root, myName: myName) {
                    return Reading(conversation: convo, composer: snapshot.elements[convo.composerHandle])
                }
            }
            return nil
        case .messenger:
            // Only a Messenger tab is read; any other page stops at its title.
            guard let window = AXSnapshot.windows(pid: pid).first,
                  AXSnapshot.title(of: window).localizedCaseInsensitiveContains("messenger") else { return nil }
            AXSnapshot.enableWebAccessibility(pid: pid)
            let snapshot = AXSnapshot(window: window, maxNodes: 8000)
            guard let convo = MessengerParser.parse(window: snapshot.root) else { return nil }
            return Reading(conversation: convo, composer: snapshot.elements[convo.composerHandle])
        case .line: return await PixelReader.shared.readLine(pid: pid)
        case .telegram: return await PixelReader.shared.readTelegram(pid: pid)
        }
    }
}
