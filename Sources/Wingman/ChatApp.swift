import AppKit
import ApplicationServices
import WingmanCore

/// A chat app Wingman can read, and how it talks.
enum ChatApp: String, CaseIterable {
    case slack, line, telegram

    var name: String {
        switch self {
        case .slack: "Slack"
        case .line: "LINE"
        case .telegram: "Telegram"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .line: ["jp.naver.line.mac"]
        case .telegram: ["ru.keepcoder.Telegram", "org.telegram.desktop"]
        }
    }

    /// LINE and Telegram draw their messages without exposing text, so they are read from pixels.
    var readsPixels: Bool { self != .slack }

    /// Reading pixels costs a capture and, when the chat changed, an OCR pass.
    var pollInterval: TimeInterval { readsPixels ? 1.2 : 0.7 }

    /// How replies should sound in this app, for the writer's rules.
    var register: String {
        switch self {
        case .slack: "這是工作用的 Slack：語氣像真人同事，自然、簡潔、有禮，不要客服腔，不要過度客套或堆砌表情符號。"
        case .line, .telegram: "這是日常通訊軟體：語氣像平常傳訊息，自然口語、簡短，可以用常見的語助詞，但不要裝熟、不要過度可愛或堆砌表情符號。"
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
        case .line: return await PixelReader.shared.readLine(pid: pid)
        case .telegram: return await PixelReader.shared.readTelegram(pid: pid)
        }
    }
}
