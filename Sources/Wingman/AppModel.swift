import AppKit
import WingmanCore

/// What Wingman knows about the Slack conversation in front of the user, and what it suggests.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case idle, thinking, ready, skipped, failed(String) }

    @Published private(set) var conversation: Conversation?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var judgment: Judgment?
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var note: String?
    @Published private(set) var ranking = false
    @Published var panelShown = false
    @Published var direction = ""
    @Published var fieldFocused = false
    @Published var hotkeyLabel = "⌥Space"
    @Published var panelWidth: CGFloat = 480
    @Published private(set) var chatInFront = false
    private(set) var app: ChatApp = .slack

    let settings = Prefs.shared
    private(set) var chatPID: pid_t?
    private var shownFingerprint = ""     // the conversation the suggestions belong to
    private var seenFingerprint = ""      // the conversation last read from screen
    private var judgedFingerprint = ""    // the conversation `judgment` is about
    private var settleTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?

    private var brain: Brain { Brain(settings: settings, app: app) }

    /// Pill text; nil hides the pill.
    var pillText: String? {
        if let note { return note }
        switch phase {
        case .idle: return nil
        case .thinking: return "正在想怎麼回…"
        case .ready: return "✦ \(candidates.count) 個建議  \(hotkeyLabel)"
        case .skipped: return "這則可以不回 · \(hotkeyLabel) 仍可寫回覆"
        case .failed: return "⚠︎ 沒有產生建議  \(hotkeyLabel)"
        }
    }

    var replyTo: ChatMessage? { conversation?.messages.last { !$0.isMe } }

    /// The draft Jev rates highest, once ranking has come back.
    var bestIndex: Int? {
        guard candidates.contains(where: { $0.score != nil }) else { return nil }
        return candidates.indices.max { (candidates[$0].score ?? 0) < (candidates[$1].score ?? 0) }
    }

    // MARK: - Screen updates

    func chatLeft() {
        chatInFront = false
        panelShown = false
    }

    func update(_ convo: Conversation?, app: ChatApp, pid: pid_t) {
        chatInFront = true
        chatPID = pid
        if app != self.app {
            self.app = app
            seenFingerprint = ""
        }
        conversation = convo
        guard let convo else { return }
        let print = fingerprint(convo)
        guard print != seenFingerprint else { return }
        seenFingerprint = print
        settleTask?.cancel()
        if print != shownFingerprint && !panelShown {
            workTask?.cancel()
            phase = .idle
            candidates = []
            judgment = nil
        }
        // Prefetch once the other side's message has sat still, so ⌥Space opens instantly.
        guard convo.awaitingReply, !settings.paused, !panelShown else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.seenFingerprint == print else { return }
            self.analyze(auto: true)
        }
    }

    // MARK: - Suggestions

    /// `auto` is the prefetch on a new message: drafts are written only when Jev says a reply is
    /// expected. A draft costs 2–3 Jev calls with DeepSeek V4.1 Flash and about 35 with Claude Haiku,
    /// and chatter should not raise a pill either way.
    func analyze(auto: Bool = false) {
        guard let convo = conversation else { return }
        workTask?.cancel()
        let print = fingerprint(convo)
        shownFingerprint = print
        // ⌥Space after a skipped prefetch: Jev already read this exact conversation.
        let reuseJudgment = !auto && judgment != nil && judgedFingerprint == print
        phase = .thinking
        candidates = []
        ranking = false
        if !reuseJudgment { judgment = nil }
        guard settings.hasWriterKey || !settings.typesafeKey.isEmpty else {
            phase = .failed(Brain.Failure.missingKey.localizedDescription)
            return
        }
        workTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            if !reuseJudgment {
                do {
                    let judgment = try await self.brain.judge(convo)
                    guard !Task.isCancelled else { return }
                    self.judgment = judgment
                    self.judgedFingerprint = print
                    Log.write("judge \(Int(Date().timeIntervalSince(started) * 1000))ms intent=\(judgment.intent)")
                } catch {
                    // Writing without Jev's picks still helps.
                    Log.write("judge failed: \(error.localizedDescription)")
                }
            }
            let picks = self.judgment?.strategies.prefix(3).map(\.name) ?? []
            if auto, let judgment = self.judgment, judgment.needsReply < 0.5 {
                self.phase = .skipped
                Log.write("drafts skipped needs_reply=\(String(format: "%.2f", judgment.needsReply))")
                return
            }
            guard self.settings.hasWriterKey else {
                // A TypeSafe key alone still answers "what do they want, how soon"; writing needs an LLM.
                self.phase = .failed("這則訊息判斷好了。填入 OpenRouter key，就能幫你寫回覆")
                return
            }
            do {
                let written = try await self.brain.write(convo, strategies: picks, judgment: self.judgment)
                guard !Task.isCancelled else { return }
                self.candidates = Array(written.prefix(3))
                self.phase = .ready
                Log.write("suggest \(Int(Date().timeIntervalSince(started) * 1000))ms candidates=\(written.count)")
                await self.rankCandidates(convo)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
                Log.write("write failed: \(error.localizedDescription)")
            }
        }
    }

    func rewrite(_ direction: String) {
        let direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let convo = conversation, !direction.isEmpty else { return }
        workTask?.cancel()
        let previous = candidates
        phase = .thinking
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let written = try await self.brain.rewrite(convo, direction: direction, previous: previous)
                guard !Task.isCancelled else { return }
                self.candidates = Array(written.prefix(3))
                self.phase = .ready
                self.direction = ""
                await self.rankCandidates(convo)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Scores arrive after the drafts; numbers stay put so a key already on its way hits the draft it meant.
    private func rankCandidates(_ convo: Conversation) async {
        let drafts = candidates.map(\.text)
        guard drafts.count > 1 else { return }
        ranking = true
        defer { ranking = false }
        let started = Date()
        do {
            let scores = try await brain.rank(convo, drafts: drafts)
            guard !Task.isCancelled, candidates.map(\.text) == drafts else { return }
            for index in candidates.indices { candidates[index].score = scores[index] }
            Log.write("rank \(Int(Date().timeIntervalSince(started) * 1000))ms")
        } catch {
            Log.write("rank failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Panel

    func togglePanel() {
        panelShown ? closePanel() : openPanel()
    }

    func openPanel() {
        guard let convo = conversation else { return }
        if fingerprint(convo) != shownFingerprint || phase == .idle || phase == .skipped { analyze() }
        if case .failed = phase { analyze() }
        panelShown = true
    }

    func closePanel() {
        panelShown = false
        fieldFocused = false
    }

    func insertBest() {
        insert(bestIndex ?? 0)
    }

    func insert(_ index: Int) {
        guard candidates.indices.contains(index), let pid = chatPID, let convo = conversation else { return }
        let text = candidates[index].text
        let app = app
        closePanel()
        Task { [weak self] in
            let outcome = await Inserter.insert(text, app: app, expectedTitle: convo.title, pid: pid)
            self?.flash(outcome.message)
        }
    }

    private func flash(_ message: String) {
        noteTask?.cancel()
        note = message
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.note = nil
        }
    }

    private func fingerprint(_ convo: Conversation) -> String {
        ([app.rawValue, convo.title, convo.isThread ? "t" : "c"] + convo.messages.suffix(4).map { "\($0.sender ?? "")|\($0.text)" })
            .joined(separator: "\u{1f}")
    }
}
