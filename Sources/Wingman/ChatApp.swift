import AppKit
import ApplicationServices
import WingmanCore

/// A chat app Wingman can read, and how it talks.
enum ChatApp: String, CaseIterable {
    case slack, discord, line, telegram, messenger, instagram, threads

    var name: String {
        switch self {
        case .slack: "Slack"
        case .discord: "Discord"
        case .line: "LINE"
        case .telegram: "Telegram"
        case .messenger: "Messenger"
        case .instagram: "Instagram"
        case .threads: "Threads"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .discord: ["com.hnc.Discord"]
        case .line: ["jp.naver.line.mac"]
        case .telegram: ["ru.keepcoder.Telegram", "org.telegram.desktop"]
        case .messenger, .instagram, .threads: Self.browsers
        }
    }

    /// Chromium browsers, which share Chrome's accessibility tree; the web chats are read in them.
    static let browsers = ["com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser"]

    /// LINE and Telegram draw their messages without exposing text, so they are read from pixels.
    var readsPixels: Bool { self == .line || self == .telegram }

    /// A browser hosts other pages too: read it, and take the shortcut, only on a web chat's tab.
    var isBrowser: Bool { WebChat(rawValue: rawValue) != nil }

    /// Electron apps build their accessibility tree only when asked (AXManualAccessibility).
    var isElectron: Bool { self == .slack || self == .discord }

    /// How replies should sound in this app, for the writer's rules.
    var register: String {
        switch self {
        case .slack: "這是工作用的 Slack：語氣像真人同事，自然、簡潔、有禮，不要客服腔，不要過度客套或堆砌表情符號。"
        case .discord: "這是 Discord 社群頻道：語氣輕鬆自然，像社群裡的成員在聊天，簡短，不要客服腔，也不要過度熱情或堆砌表情符號。"
        case .line, .telegram, .messenger, .instagram, .threads: "這是日常通訊軟體：語氣像平常傳訊息，自然口語、簡短，可以用常見的語助詞，但不要裝熟、不要過度可愛或堆砌表情符號。"
        }
    }

}

/// What is in front, when Wingman may read it: a chat app, or a browser, whose tab decides which web
/// chat (if any) it is. Apps switched off in settings are never in front as far as Wingman is concerned.
enum Front: Equatable {
    case app(ChatApp, pid_t)
    case browser(pid_t)

    static var current: Front? {
        guard let running = NSWorkspace.shared.frontmostApplication, let id = running.bundleIdentifier else { return nil }
        let off = Prefs.storedDisabledApps
        if ChatApp.browsers.contains(id) {
            let anyOn = WebChat.allCases.contains { !off.contains($0.rawValue) }
            return anyOn ? .browser(running.processIdentifier) : nil
        }
        guard let app = ChatApp.allCases.first(where: { $0.bundleIDs.contains(id) }), !off.contains(app.rawValue)
        else { return nil }
        return .app(app, running.processIdentifier)
    }

    var pid: pid_t {
        switch self { case let .app(_, pid), let .browser(pid): pid }
    }

    /// The chat app itself; nil for a browser until a read finds a web chat in its tab.
    var app: ChatApp? {
        if case let .app(app, _) = self { app } else { nil }
    }

    /// Reading pixels costs a capture and, when the chat changed, an OCR pass.
    var pollInterval: TimeInterval { app.map { $0.readsPixels ? 1.2 : 0.7 } ?? 1.0 }
}

/// A conversation read from screen, plus the input element to type into when the app exposes one.
struct Reading {
    var conversation: Conversation
    var composer: AXUIElement?
}

enum Readers {
    /// What is in front shows, and which chat app that turned out to be.
    static func read(_ front: Front, myName: String?) async -> (app: ChatApp, reading: Reading)? {
        switch front {
        case let .app(app, pid): await read(app, pid: pid, myName: myName).map { (app, $0) }
        case let .browser(pid): readBrowser(pid: pid)
        }
    }

    /// `app`'s conversation; for a web chat, only while the browser's front tab is still that chat.
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
        case .messenger, .instagram, .threads:
            guard let (shown, reading) = readBrowser(pid: pid), shown == app else { return nil }
            return reading
        case .line: return await PixelReader.shared.readLine(pid: pid)
        case .telegram: return await PixelReader.shared.readTelegram(pid: pid, myName: myName)
        }
    }

    /// Only a tab showing a web chat that is switched on is read, or on Instagram and Threads the post a reply
    /// is being written under; any other page stops at its address.
    private static func readBrowser(pid: pid_t) -> (app: ChatApp, reading: Reading)? {
        guard let window = AXSnapshot.windows(pid: pid).first else { return nil }
        let url = AXSnapshot.pageURL(of: window)
        if let url, let chat = WebChat.at(url), let app = ChatApp(rawValue: chat.rawValue) {
            guard !Prefs.storedDisabledApps.contains(app.rawValue) else { return nil }
            let snapshot = AXSnapshot(window: window, maxNodes: 8000)
            guard let convo = MessengerParser.parse(window: snapshot.root) else { return nil }
            return (app, Reading(conversation: convo, composer: snapshot.elements[convo.composerHandle]))
        }
        if let url, let chat = WebChat.posts(url), let app = ChatApp(rawValue: chat.rawValue) {
            guard !Prefs.storedDisabledApps.contains(app.rawValue) else { return nil }
            return readPost(pid: pid).map { (app, $0) }
        }
        // The address only appears once the browser builds the page's tree; a tab titled like a web chat
        // switches that on, and the next read checks the address before anything else.
        if url == nil, WebChat.mayBe(title: AXSnapshot.title(of: window)) { AXSnapshot.enableWebAccessibility(pid: pid) }
        return nil
    }

    /// Nothing is read unless a text box has focus. Then the view widens from that box a few levels at a time
    /// until it takes in the post the box belongs to: a few levels on a post's page, more in a feed. Only that
    /// part of the page is copied, never the whole feed.
    private static func readPost(pid: pid_t) -> Reading? {
        guard let box = AXSnapshot.focusedElement(pid: pid), AXSnapshot.role(of: box) == "AXTextArea" else { return nil }
        var around = box
        for level in 1...18 {
            guard let parent = AXSnapshot.parent(of: around) else { break }
            around = parent
            let top = AXSnapshot.role(of: parent) == "AXWebArea"
            guard level % 3 == 0 || top else { continue }
            let snapshot = AXSnapshot(window: around, maxNodes: 4000)
            if let convo = PostParser.parse(window: snapshot.root) {
                return Reading(conversation: convo, composer: snapshot.elements[convo.composerHandle])
            }
            if top { break }
        }
        return nil
    }
}
