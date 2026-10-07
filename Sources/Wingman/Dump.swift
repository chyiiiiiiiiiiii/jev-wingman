import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import WingmanCore

/// `Wingman --dump [--full]`: print what Wingman reads from Slack right now, then exit.
/// Text is redacted to its first two characters unless `--full` is given.
enum Dump {
    static func run(full: Bool, trace: Bool, wait: Bool) -> Int32 {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to the process running this command.")
            return 1
        }
        guard let slack = Slack.running else {
            print("Slack is not running.")
            return 1
        }
        AXSnapshot.enableWebAccessibility(pid: slack.processIdentifier)
        if wait {
            print("5 秒後讀取，請切到 Slack…")
            Thread.sleep(forTimeInterval: 5)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let myName = Prefs.storedMyName
        let show = { (s: String) in full || s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
        guard let (convo, snapshot) = Slack.read(pid: slack.processIdentifier, myName: myName) else {
            print("No Slack composer found. Windows Slack reports:")
            for window in AXSnapshot.windows(pid: slack.processIdentifier) {
                let root = AXSnapshot(window: window).root
                var nodes = 0, editors: [String] = []
                func visit(_ node: UINode) {
                    nodes += 1
                    if node.role == "AXTextArea" || node.role == "AXTextField" {
                        editors.append("\(node.role)[\(node.classes.prefix(2).joined(separator: "."))]")
                    }
                    node.children.forEach(visit)
                }
                visit(root)
                print("  \(show(root.title)) \(Int(root.frame.width))x\(Int(root.frame.height)) · \(nodes) nodes · "
                      + "text inputs: \(editors.isEmpty ? "none" : editors.joined(separator: ", "))")
            }
            return 1
        }
        print("nodes \(snapshot.elements.count) · me \(myName.map(show) ?? "(not set)")")
        print("title \(show(convo.title)) · \(convo.isThread ? "thread" : "channel") · draft \(convo.draft.count) chars")
        print("composer \(Int(convo.composerFrame.minX)),\(Int(convo.composerFrame.minY)) \(Int(convo.composerFrame.width))x\(Int(convo.composerFrame.height))")
        for m in convo.messages {
            let who = m.isMe ? "me" : (m.sender.map(show) ?? "?")
            let lines = m.text.split(separator: "\n").map { show(String($0)) }.joined(separator: " ⏎ ")
            print("  [\(who)] \(m.time.map(show) ?? "-") · \(lines)")
        }
        print("awaiting reply: \(convo.awaitingReply)")
        if trace { printTrace(snapshot.root, composer: convo.composerFrame, show: show) }
        return 0
    }

    /// `--dump --app <slack|discord|line|telegram|messenger|instagram|threads> [--wait]`: what the app's reader sees now.
    static func read(app: ChatApp, wait: Bool) async -> Int32 {
        guard AXIsProcessTrusted() else { print("Accessibility is not granted to this process."); return 1 }
        guard let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier.map(app.bundleIDs.contains) == true
        }) else {
            print("\(app.name) is not running."); return 1
        }
        if wait {
            print("5 秒後讀取，請切到 \(app.name)…")
            try? await Task.sleep(for: .seconds(5))
        }
        if app.isElectron || app.isBrowser {
            // Chromium builds the page tree a moment after it is asked; watch it arrive.
            AXSnapshot.enableWebAccessibility(pid: running.processIdentifier)
            var counts: [String] = []
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(1))
                let window = AXSnapshot.windows(pid: running.processIdentifier).first
                let size = window.map { AXSnapshot(window: $0, maxNodes: 8000).elements.count } ?? 0
                counts.append("\(size)\(window.flatMap(AXSnapshot.pageURL(of:)) == nil ? "" : "+page")")
            }
            print("nodes over 6 s after enabling: " + counts.joined(separator: " → "))
        }
        guard let reading = await Readers.read(app, pid: running.processIdentifier, myName: Prefs.storedMyName) else {
            // Which gate stopped it: the window, its title, the tree, or the message box.
            let windows = AXSnapshot.windows(pid: running.processIdentifier)
            print("\(app.name): nothing read · \(windows.count) window(s)")
            for window in windows.prefix(3) {
                let title = AXSnapshot.title(of: window)
                let root = AXSnapshot(window: window, maxNodes: 8000).root
                var nodes = 0, inputs: [String] = []
                func visit(_ node: UINode) {
                    nodes += 1
                    if ["AXTextArea", "AXTextField", "AXComboBox"].contains(node.role) {
                        let label = [node.title, node.desc].max { $0.count < $1.count } ?? ""
                        inputs.append("\(node.role) “\(label.prefix(4))…”(\(label.count))")
                    }
                    node.children.forEach(visit)
                }
                visit(root)
                let page = AXSnapshot.pageURL(of: window).map { "\($0.host ?? "?")\($0.path.prefix(10))" } ?? "no page"
                let chat = AXSnapshot.pageURL(of: window).flatMap(WebChat.at)?.rawValue ?? "none"
                print("  window “\(title.prefix(2))…”(\(title.count)) · \(page) · web chat: \(chat) · "
                      + "\(nodes) nodes · inputs: \(inputs.isEmpty ? "none" : inputs.joined(separator: ", "))")
            }
            return 1
        }
        let convo = reading.conversation
        let show = { (s: String) in s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
        print("\(app.name): “\(show(convo.title))” · \(convo.messages.count) messages · composer \(reading.composer == nil ? "none" : "found") · awaiting reply \(convo.awaitingReply)")
        for message in convo.messages.suffix(12) {
            print("  [\(message.isMe ? "me" : (message.sender.map(show) ?? "them"))] \(show(message.text))")
        }
        if app.isBrowser {
            let pane = MessengerParser.lastPane
            print(String(format: "text lines in the column x %.0f–%.0f, y %.0f–%.0f:", pane.minX, pane.maxX, pane.minY, pane.maxY))
            for line in MessengerParser.lastLines.sorted(by: { $0.frame.minY < $1.frame.minY }) {
                print(String(format: "  y=%4.0f h=%2.0f x=%4.0f–%4.0f ", line.frame.minY, line.frame.height, line.frame.minX, line.frame.maxX) + show(line.text))
            }
        }
        return 0
    }

    /// `--check-history`: keep a made-up chat the way 記住聊天紀錄 does, read it back, look at the file on disk,
    /// then remove what the check made (and the key, if the check was the one to create it).
    static func checkHistory() -> Int32 {
        let chat = "check|wingman-self-test"
        let hadKey = Keychain.get(account: "history") != nil, before = ChatHistory.count
        let messages = [ChatMessage(sender: "Mia", text: "自我檢查：這則會加密存起來再讀回來"),
                        ChatMessage(sender: "我", text: "收到", isMe: true)]
        ChatHistory.save(chat, messages)
        let file = ChatHistory.folder.appendingPathComponent(HistoryCodec.fileName(for: chat))
        let back = ChatHistory.load(chat)
        let plaintext = String(decoding: (try? Data(contentsOf: file)) ?? Data(), as: UTF8.self).contains("自我檢查")
        let excluded = (try? ChatHistory.folder.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true
        try? FileManager.default.removeItem(at: file)
        if !hadKey && before == 0 { ChatHistory.eraseAll() }
        print("round trip \(back == messages) · words readable on disk \(plaintext) · out of backups \(excluded) · "
              + "left behind \(ChatHistory.count - before) files")
        return back == messages && !plaintext && excluded ? 0 : 1
    }

    /// `--check-idle`: show the suggestion panel once while nothing is written yet, put it away, and measure how
    /// much CPU Wingman then spends doing nothing. Above 1% of a core fails: a hidden panel must cost nothing.
    @MainActor
    static func checkIdle() -> Int32 {
        Prefs.usesKeychain = false
        NSApplication.shared.setActivationPolicy(.accessory)
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let convo = Conversation(title: "#dev", isThread: false,
                                 messages: [ChatMessage(sender: "Mia", text: "API 文件今天來得及更新嗎？")], draft: "",
                                 composerHandle: -1, composerFrame: CGRect(x: screen.midX - 280, y: screen.midY, width: 560, height: 40))
        let model = AppModel()
        let panels = PanelController(model: model)
        model.present(convo, judgment: nil, candidates: [], phase: .thinking)
        model.panelShown = true
        panels.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        model.closePanel()
        panels.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        func cpu() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let before = cpu(), seconds = 5.0
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        let share = (cpu() - before) / seconds * 100
        print(String(format: "idle with the panel put away: %.1f%% of one core over %.0f s", share, seconds))
        return share < 1 ? 0 : 1
    }

    /// `--try-panel`: the suggestion panel, live, over a made-up chat in the middle of the screen, to try its keys and
    /// focus by hand or by script. Nothing is typed anywhere and nothing is sent: there is no chat to type into and no
    /// key to write with; what would be logged, picks included, is printed instead.
    @MainActor
    static func tryPanel() -> Never {
        Prefs.usesKeychain = false
        Log.toStandardOutput = true
        NSApplication.shared.setActivationPolicy(.accessory)
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let model = AppModel()
        model.loadSample(phase: .ready)
        var convo = model.conversation!
        convo.composerFrame = CGRect(x: screen.midX - 280, y: screen.height * 0.8, width: 560, height: 40)
        model.present(convo, judgment: model.judgment, candidates: model.candidates, phase: .ready)
        let panels = PanelController(model: model)
        model.panelShown = true
        panels.refresh()
        print("panel up; Ctrl-C to quit")
        // Each change of what the keys act on, for a script to follow.
        var last = ""
        let watch = model.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                let phase = switch model.phase { case .failed: "failed"; default: "\(model.phase)" }
                let state = "shown=\(model.panelShown) field=\(model.fieldFocused) direction=\"\(model.direction)\" "
                    + "selected=\(model.selected) phase=\(phase)"
                if state != last { last = state; print(state); fflush(stdout) }
            }
        }
        NSApplication.shared.run()
        watch.cancel()
        exit(0)
    }

    /// `--check-jev`: ask Jev about four made-up chats (calm, tense, a request, a question sent in two messages) with the
    /// keys in settings, and print what comes back (never the keys), to see the questions still suit the model after
    /// they change.
    static func checkJev() async -> Int32 {
        func line(_ text: String, me: Bool = false) -> ChatMessage { ChatMessage(sender: me ? "我" : "Mia", text: text, isMe: me) }
        let chats = [
            ("calm", [line("早安～今天的站會改到十點喔"), line("好，收到", me: true), line("API 文件今天來得及更新嗎？")]),
            ("tense", [line("你上週說週三前會給我文件"), line("再等我一下，快好了", me: true),
                       line("你每次都這樣說"), line("算了，你忙你的吧，我自己弄")]),
            ("request", [line("午安"), line("可以幫我 review 一下登入那個 PR 嗎？今天下班前要合")]),
            ("burst", [line("早"), line("早安", me: true), line("週五晚上要不要一起吃飯？"), line("哈哈")]),
        ]
        let brain = Brain(settings: Prefs.shared, app: .slack)
        for (name, messages) in chats {
            let convo = Conversation(title: "#dev", isThread: false, messages: messages, draft: "",
                                     composerHandle: -1, composerFrame: .zero)
            let started = Date()
            do {
                let j = try await brain.judge(convo)
                print(String(format: "%@ · %d ms · intent %@ (%.2f) · needs reply %.2f · urgency %.2f · tension %@ · subtext %@",
                             name, Int(Date().timeIntervalSince(started) * 1000), j.intent, j.intentConfidence, j.needsReply,
                             j.urgency ?? -1, j.tension.map { String(format: "%.2f", $0) } ?? "none",
                             j.subtext.map { String(format: "%.2f", $0) } ?? "none"))
                print("  Jev's top three: \(j.strategies.prefix(3).map(\.name).joined(separator: " / ")) · drafted: "
                      + ReplyQuestions.picks(from: j.strategies, tense: (j.tension ?? 0) >= Brain.tense).joined(separator: " / "))
            } catch {
                print("\(name): \(error.localizedDescription)")
                return 1
            }
        }
        return 0
    }

    /// `--dump --app <instagram|threads> --pretend-focus`: read the front tab as if its first text box had focus,
    /// to check the post reader on a real page without clicking into a box where Enter would post.
    static func post(app: ChatApp) -> Int32 {
        guard AXIsProcessTrusted(),
              let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier.map(app.bundleIDs.contains) == true }),
              let window = AXSnapshot.windows(pid: running.processIdentifier).first
        else { print("Not trusted, or no \(app.name) window."); return 1 }
        var root = AXSnapshot(window: window, maxNodes: 8000).root
        func focusFirstBox(_ node: inout UINode) -> Bool {
            if node.role == "AXTextArea" { node.focused = true; return true }
            for index in node.children.indices where focusFirstBox(&node.children[index]) { return true }
            return false
        }
        guard focusFirstBox(&root), let convo = PostParser.parse(window: root) else { print("\(app.name): no post read"); return 1 }
        let show = { (s: String) in s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
        print("\(app.name) post: “\(show(convo.title))” · box \(Int(convo.composerFrame.minX)),\(Int(convo.composerFrame.minY)) · draft \(convo.draft.count) chars")
        for message in convo.messages {
            let lines = message.text.split(separator: "\n").map { show(String($0)) }.joined(separator: " ⏎ ")
            print("  [\(show(message.sender ?? "?"))] \(lines)")
        }
        return 0
    }

    /// `--probe <bundle id> [--wait] [--host <domain>]`: role, DOM classes and redacted text of every labelled
    /// node in an app's window, to learn where a new app keeps its messages before writing its reader.
    /// `--host` picks the browser window showing that site, in front or not.
    static func probe(bundleID: String, wait: Bool, region: ClosedRange<Double> = 0.2...1, limit: Int = 260,
                      host: String? = nil) -> Int32 {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { print("Not trusted, or \(bundleID) is not running."); return 1 }
        AXSnapshot.enableWebAccessibility(pid: app.processIdentifier)
        if wait {
            print("5 秒後讀取，請切到 \(app.localizedName ?? bundleID)…")
            Thread.sleep(forTimeInterval: 5)
        }
        // Electron builds its tree a few seconds after accessibility is switched on.
        var root: UINode?, counts: [Int] = []
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 1)
            let windows = AXSnapshot.windows(pid: app.processIdentifier)
            let showing = host.map { host in
                windows.first { AXSnapshot.pageURL(of: $0)?.host?.lowercased().hasSuffix(host) == true }
            } ?? windows.first
            guard let window = showing else { counts.append(0); continue }
            let snapshot = AXSnapshot(window: window)
            root = snapshot.root
            counts.append(snapshot.elements.count)
            if counts.count >= 2, counts.last! > 100, counts.last! == counts[counts.count - 2] { break }
        }
        print("front app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") · nodes over time: "
              + counts.map(String.init).joined(separator: " → "))
        guard let root else { print("No window."); return 1 }
        print("window \(Int(root.frame.width))x\(Int(root.frame.height)) “\(root.title.prefix(2))…”")
        let show = { (s: String) in s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
        var printed = 0
        func visit(_ node: UINode, _ depth: Int) {
            guard printed < limit else { return }
            let f = node.frame
            let x = (f.minX - root.frame.minX) / max(root.frame.width, 1), y = (f.minY - root.frame.minY) / max(root.frame.height, 1)
            if (!node.classes.isEmpty || !node.text.isEmpty) && region.contains(Double(x)) && f.height > 1 {
                print(String(repeating: " ", count: min(depth, 24))
                      + String(format: "%@ x=%.2f y=%.2f %@ %@", node.role, x, y,
                               node.text.isEmpty ? "" : "“\(show(node.text))”", node.classes.prefix(3).joined(separator: ".")))
                printed += 1
            }
            node.children.forEach { visit($0, depth + 1) }
        }
        visit(root, 0)
        print("printed \(printed)")
        return 0
    }

    /// Every text node in the conversation pane with the classes of its nearest ancestors, to find
    /// which Slack element a stray line in a message came from.
    private static func printTrace(_ root: UINode, composer: CGRect, show: (String) -> String) {
        print("--- text nodes in the pane, with ancestor classes")
        func visit(_ node: UINode, _ path: [String]) {
            let path = node.classes.isEmpty ? path : path + [node.classes.prefix(2).joined(separator: ".")]
            let f = node.frame
            if node.role == "AXStaticText", !node.value.isEmpty, f.height > 1, f.maxY <= composer.minY,
               f.minX >= composer.minX - 8, f.minX < composer.maxX {
                print("  \(show(node.value))  ←  \(path.suffix(3).joined(separator: " › "))")
            }
            node.children.forEach { visit($0, path) }
        }
        visit(root, [])
    }
}
