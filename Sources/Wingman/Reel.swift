import AppKit
import SwiftUI
import WingmanCore

/// The screens of a promo video, drawn by the app itself from made-up chats in promo/<name>/.
///
/// `Wingman --stage <dir> [--only a,b]` runs the chats marked `stage` in chats.json through the real
/// pipeline once (Jev judges, the writer drafts, Jev ranks) and keeps what came back in staged.json.
/// `Wingman --render-reel <dir> <out>` then draws reel.json's beats from it as 1080×1920 frames, a
/// transparent overlay per beat for its caption and key, the sounds, and beats.json for
/// scripts/make-reel.py. Every panel in the video says what Wingman really said, and redrawing costs nothing.
enum Reel {
    struct Script: Decodable { let chats: [String: Chat] }

    struct Chat: Decodable {
        let app: String
        let title: String
        var post: Bool?
        var stage: Bool?
        /// A group or channel: names go above the bubbles.
        var group: Bool?
        /// The chat this one carries on from: its messages come first.
        var from: String?
        let messages: [Line]
    }

    struct Line: Decodable {
        let from: String
        var time: String?
        /// "📎" for a picture; "$chat" for the draft Wingman rated best for that chat.
        let text: String
        /// What the picture shows, drawn as a label.
        var image: String?
        var isMe: Bool { from == "我" }
    }

    /// What Wingman said about one chat.
    struct Said: Codable {
        struct Draft: Codable {
            var strategy: String
            var text: String
            var score: Double?
        }

        var intent: String
        var intentConfidence: Double
        var needsReply: Double
        var urgency: Double?
        var tension: Double?
        var subtext: Double?
        var strategies: [String]
        var drafts: [Draft]

        var judgment: Judgment {
            Judgment(intent: intent, intentConfidence: intentConfidence, needsReply: needsReply, urgency: urgency,
                     strategies: strategies.map { Strategy(name: $0, probability: 0) }, tension: tension, subtext: subtext)
        }
        var candidates: [Candidate] { drafts.map { Candidate(strategy: $0.strategy, text: $0.text, score: $0.score) } }
        var best: String { drafts.max { ($0.score ?? 0) < ($1.score ?? 0) }?.text ?? "" }
    }

    struct Beat: Decodable {
        let seconds: Double
        var caption: String?
        /// A shot to be filmed; the drawn lead acts it out until the footage is in.
        var side: String?
        var shot: String?
        var chat: String?
        /// How many of the chat's own messages are in yet; all when absent.
        var show: Int?
        var typed: String?
        /// Words the user put in place of the draft's blanks, such as "[時間]": "12 點".
        var fill: [String: String]?
        var panel: Bool?
        /// "auto": the pill as it reads once the chat was looked at; "note": the pill after a draft is typed in.
        var pill: String?
        var key: String?
        var sound: String?
        /// Seconds into the beat the sound starts; at its start when absent.
        var soundAt: Double?
        var end: Bool?
    }

    struct Spec: Decodable { let beats: [Beat] }

    static func load<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func lines(_ id: String, _ script: Script, show: Int? = nil) -> [Line] {
        guard let chat = script.chats[id] else { return [] }
        return (chat.from.map { lines($0, script) } ?? []) + chat.messages.prefix(show ?? chat.messages.count)
    }

    static func resolve(_ text: String, _ said: [String: Said]) -> String {
        text.hasPrefix("$") ? said[String(text.dropFirst())]?.best ?? text : text
    }

    static func conversation(_ id: String, _ script: Script, _ said: [String: Said], show: Int? = nil) -> Conversation {
        let chat = script.chats[id]!
        let messages = lines(id, script, show: show).map {
            ChatMessage(sender: $0.isMe ? nil : $0.from, time: $0.time, text: resolve($0.text, said), isMe: $0.isMe)
        }
        return Conversation(title: chat.title, isThread: false, messages: messages, draft: "", composerHandle: -1,
                            composerFrame: .zero, isPost: chat.post == true)
    }

    // MARK: - Staging

    static func stage(_ directory: String, only: [String]) async -> Int32 {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let out = folder.appendingPathComponent("staged.json")
        guard let script = try? load(Script.self, folder.appendingPathComponent("chats.json")) else {
            print("No readable chats.json in \(folder.path)")
            return 1
        }
        var said = (try? load([String: Said].self, out)) ?? [:]
        for id in script.chats.keys.sorted() where script.chats[id]?.stage == true && (only.isEmpty || only.contains(id)) {
            let chat = script.chats[id]!
            guard let app = ChatApp(rawValue: chat.app) else { print("\(id): no app \(chat.app)"); return 1 }
            let convo = conversation(id, script, said)
            let brain = Brain(settings: Prefs.shared, app: app)
            do {
                let j = try await brain.judge(convo)
                var drafts = try await brain.write(convo, strategies: j.strategies.prefix(3).map(\.name), judgment: j) { _ in }
                drafts = Array(drafts.prefix(3))
                let scores = try await brain.rank(convo, drafts: drafts.map(\.text), tense: (j.tension ?? 0) >= Brain.tense)
                said[id] = Said(intent: j.intent, intentConfidence: j.intentConfidence, needsReply: j.needsReply,
                                urgency: j.urgency, tension: j.tension, subtext: j.subtext,
                                strategies: j.strategies.prefix(3).map(\.name),
                                drafts: zip(drafts, scores).map { Said.Draft(strategy: $0.strategy, text: $0.text, score: $1) })
                print(String(format: "%@ · %@ (%.2f) · needs reply %.2f · urgency %@ · tension %@ · subtext %@",
                             id, j.intent, j.intentConfidence, j.needsReply, format(j.urgency), format(j.tension), format(j.subtext)))
                for (draft, score) in zip(drafts, scores) { print(String(format: "  %.2f  [%@] %@", score, draft.strategy, draft.text)) }
            } catch {
                print("\(id): \(error.localizedDescription)")
                return 1
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do { try encoder.encode(said).write(to: out) } catch { print("Could not write \(out.path)"); return 1 }
        return 0
    }

    private static func format(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "none" }

    // MARK: - Drawing

    static let canvas = CGSize(width: 450, height: 800)    // points; drawn at 2.4× into 1080×1920

    @MainActor
    static func render(_ directory: String, to output: String) -> Int32 {
        Prefs.usesKeychain = false
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let out = URL(fileURLWithPath: output, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard let script = try? load(Script.self, folder.appendingPathComponent("chats.json")),
              let spec = try? load(Spec.self, folder.appendingPathComponent("reel.json")) else {
            print("Needs chats.json and reel.json in \(folder.path)")
            return 1
        }
        let said = (try? load([String: Said].self, folder.appendingPathComponent("staged.json"))) ?? [:]
        var listed: [[String: Any]] = []
        for (index, beat) in spec.beats.enumerated() {
            let frame = String(format: "frame-%02d.png", index + 1)
            let overlay = String(format: "overlay-%02d.png", index + 1)
            if beat.end == true {
                write(EndCard(), to: out.appendingPathComponent(frame))
            } else if let side = beat.side {
                // Drawn until the shot is filmed: the lead acts it out at 30 frames a second.
                write(ReelCharacter(shot: side, t: 0), to: out.appendingPathComponent(frame))
                for index in 0..<Int((beat.seconds * 30).rounded()) {
                    write(ReelCharacter(shot: side, t: Double(index) / 30),
                          to: out.appendingPathComponent(String(format: "side-%@-%03d.png", side, index)))
                }
            } else if let id = beat.chat, let chat = script.chats[id] {
                if (beat.panel == true || beat.pill == "auto"), said[id] == nil {
                    print("\(id) is not staged yet: run --stage first")
                    return 1
                }
                write(ChatScreen(beat: beat, chat: chat, lines: lines(id, script, show: beat.show),
                                 model: model(for: beat, id, script, said), said: said),
                      to: out.appendingPathComponent(frame))
            }
            write(Overlay(caption: beat.caption, key: beat.key), to: out.appendingPathComponent(overlay))
            var entry: [String: Any] = ["frame": frame, "overlay": overlay, "seconds": beat.seconds]
            if let sound = beat.sound { entry["sound"] = sound }
            if let at = beat.soundAt { entry["soundAt"] = at }
            if let side = beat.side {
                entry["side"] = side
                entry["sequence"] = "side-\(side)-%03d.png"
            }
            listed.append(entry)
        }
        let beats = try? JSONSerialization.data(withJSONObject: listed, options: [.prettyPrinted, .sortedKeys])
        try? beats?.write(to: out.appendingPathComponent("beats.json"))
        for event in Chime.Event.allCases {
            try? Chime.wav(Chime.samples(.wood, event)).write(to: out.appendingPathComponent("sound-\(event).wav"))
        }
        print("\(spec.beats.count) beats in \(out.path)")
        return 0
    }

    @MainActor
    private static func model(for beat: Beat, _ id: String, _ script: Script, _ said: [String: Said]) -> AppModel {
        let model = AppModel()
        model.panelWidth = 420
        model.hotkeyLabel = "⌥Space"
        let convo = conversation(id, script, said, show: beat.show)
        if beat.pill == "note" {
            model.present(convo, judgment: nil, candidates: [], phase: .idle, note: L("已填入，檢查後按 Enter 送出"))
        } else if let said = said[id] {
            // A prefetch writes nothing when Jev says no reply is expected; ⌥Space still would.
            let skipped = beat.panel != true && said.needsReply < 0.5
            model.present(convo, judgment: said.judgment, candidates: skipped ? [] : said.candidates,
                          phase: skipped ? .skipped : .ready)
        }
        return model
    }

    @MainActor
    private static func write(_ view: some View, to file: URL) {
        let host = NSHostingView(rootView: view.frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame.size = canvas
        // Materials need a window to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1080, pixelsHigh: 1920, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = canvas
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
    }
}

// MARK: - Views

/// Where things sit on the 450×800 canvas: Instagram covers the top ~90 points with its header and the
/// bottom ~190 with the caption and buttons, so captions go just under the top and the chat in between.
private enum Layout {
    static let captionTop: CGFloat = 96
    static let captionHeight: CGFloat = 104
    static let windowTop: CGFloat = 206
    static let windowSize = CGSize(width: 414, height: 400)
    static let keyTop: CGFloat = 612
    static let background = LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.07),
                                                    Color(red: 0.08, green: 0.07, blue: 0.14)],
                                           startPoint: .top, endPoint: .bottom)
    static func chinese(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("PingFang TC", size: size).weight(weight)
    }
}

private struct Overlay: View {
    let caption: String?
    let key: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let caption {
                Text(caption)
                    .font(Layout.chinese(29, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                    .frame(height: Layout.captionHeight)
                    .padding(.top, Layout.captionTop)
            }
            if let key {
                Text(key)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 3)
                    .padding(.top, Layout.keyTop)
            }
        }
    }
}

private struct ChatScreen: View {
    let beat: Reel.Beat
    let chat: Reel.Chat
    let lines: [Reel.Line]
    let model: AppModel
    let said: [String: Reel.Said]

    private var app: ChatApp? { ChatApp(rawValue: chat.app) }
    private var group: Bool { chat.group == true }

    var body: some View {
        ZStack(alignment: .top) {
            Layout.background
            if beat.panel == true {
                // The panel alone, as large as it reads on a phone; it rests on this chat's message box.
                VStack(spacing: 10) {
                    HStack { appChip; Text(chat.post == true ? "留言" : chat.title).font(Layout.chinese(14, .semibold)) }
                    SuggestionView(model: model)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.13, green: 0.13, blue: 0.15)))
                }
                .padding(.top, Layout.windowTop)
            } else {
                window
                    .frame(width: Layout.windowSize.width, height: Layout.windowSize.height)
                    .padding(.top, Layout.windowTop)
            }
        }
    }

    private var window: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                header
                Divider()
                messages
                composer
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.11, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12)))
            if beat.pill != nil {
                HStack { Spacer(); PillView(model: model) }.padding(.trailing, 14).padding(.bottom, 60)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            appChip
            Text(chat.post == true ? "留言" : chat.title).font(Layout.chinese(15, .semibold)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private var appChip: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(app?.name ?? chat.app).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 10) {
            if chat.post == true, let post = lines.first {
                postCard(post)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    // Like the apps: one time under a run of messages sent together.
                    let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
                    bubble(line, timed: next?.from != line.from || next?.time != line.time)
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 12)
        .padding(.bottom, beat.pill == nil ? 12 : 40)    // the pill sits over the box's top edge
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
        .clipped()
    }

    private func bubble(_ line: Reel.Line, timed: Bool) -> some View {
        let text = Reel.resolve(line.text, said)
        return VStack(alignment: line.isMe ? .trailing : .leading, spacing: 3) {
            if group && !line.isMe {
                Text(line.from).font(Layout.chinese(11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if line.isMe && timed { time(line) }
                if line.text == BubbleParser.attachment {
                    picture(line.image ?? "")
                } else {
                    // Long messages wrap at a bubble's width; short ones keep their own.
                    Text(text)
                        .font(Layout.chinese(15))
                        .frame(width: text.count > 16 ? 256 : nil, alignment: .leading)
                        .fixedSize(horizontal: text.count <= 16, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(line.isMe ? Color(red: 0.22, green: 0.30, blue: 0.52) : Color(white: 0.21),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                if !line.isMe && timed { time(line) }
            }
        }
        .frame(maxWidth: .infinity, alignment: line.isMe ? .trailing : .leading)
    }

    @ViewBuilder private func time(_ line: Reel.Line) -> some View {
        if let time = line.time { Text(time).font(.system(size: 10)).foregroundStyle(.tertiary) }
    }

    /// A picture in the chat, as a card saying what it is: a screenshot is phone-shaped.
    private func picture(_ label: String) -> some View {
        let screenshot = label == "截圖"
        return VStack(spacing: 6) {
            Image(systemName: screenshot ? "iphone.gen3" : "sun.horizon.fill")
                .font(.system(size: screenshot ? 22 : 30))
                .foregroundStyle(screenshot ? Color.white.opacity(0.6) : Color.orange)
            Text(label).font(Layout.chinese(12, .medium)).foregroundStyle(.secondary)
        }
        .frame(width: screenshot ? 64 : 150, height: screenshot ? 96 : 96)
        .background(screenshot ? Color(white: 0.28) : Color(red: 0.32, green: 0.24, blue: 0.20),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func postCard(_ post: Reel.Line) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.teal.opacity(0.8)).frame(width: 30, height: 30)
                    .overlay(Text(String(post.from.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)))
                Text(post.from).font(.system(size: 14, weight: .semibold))
                time(post)
            }
            Text(post.text).font(Layout.chinese(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                ForEach(["heart", "bubble.right", "arrow.2.squarepath", "paperplane"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var composer: some View {
        let typed = beat.typed.map { text in
            (beat.fill ?? [:]).reduce(Reel.resolve(text, said)) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
        }
        let placeholder = chat.post == true ? "回覆 \(lines.first?.from ?? "")…" : "輸入訊息"
        return HStack(spacing: 0) {
            Text(typed.flatMap { $0.isEmpty ? nil : $0 } ?? placeholder)
                .font(Layout.chinese(14))
                .foregroundStyle(typed?.isEmpty == false ? .primary : .secondary)
                .lineLimit(2)
            if typed != nil { Rectangle().fill(.primary).frame(width: 1.5, height: 17).padding(.leading, 1) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.18)))
        .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 4)
    }

    private var tint: Color {
        switch app {
        case .slack: Color(red: 0.88, green: 0.12, blue: 0.35)
        case .discord: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .line: Color(red: 0.02, green: 0.78, blue: 0.33)
        case .telegram, .messenger: Color(red: 0.16, green: 0.6, blue: 0.95)
        case .instagram: Color(red: 0.88, green: 0.19, blue: 0.62)
        case .threads, nil: Color.white
        }
    }
}

private struct EndCard: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.13, green: 0.11, blue: 0.33), Color(red: 0.04, green: 0.05, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().frame(width: 112, height: 112)
                Text("Wingman").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("不知道怎麼回？").font(Layout.chinese(24, .semibold))
                HStack(spacing: 8) {
                    keycap("⌥ Space"); Text("叫它").font(Layout.chinese(18))
                    keycap("↩ Enter"); Text("填入").font(Layout.chinese(18))
                }
                Text("Jev 判斷 · 你決定 · 不會自動送出").font(Layout.chinese(15)).foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text("Slack · Discord · LINE · Telegram · Messenger · Instagram · Threads")
                    .font(.system(size: 11.5)).foregroundStyle(.tertiary)
                Text("Mac 版測試中 · 留言「僚機」開放時通知你")
                    .font(Layout.chinese(17, .bold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color(red: 0.31, green: 0.27, blue: 0.90), in: Capsule())
                    .padding(.top, 10)
            }
            .padding(.top, 150)
        }
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.3)))
    }
}
