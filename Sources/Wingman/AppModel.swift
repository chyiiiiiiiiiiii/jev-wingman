import AppKit
import WingmanCore

/// What Wingman knows about the Slack conversation in front of the user, and what it suggests.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case idle, thinking, ready, failed(String) }

    @Published private(set) var conversation: Conversation?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var judgment: Judgment?
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var note: String?
    @Published var panelShown = false
    @Published var direction = ""
    @Published var fieldFocused = false
    @Published var hotkeyLabel = "⌥Space"
    @Published var panelWidth: CGFloat = 480
    @Published private(set) var slackInFront = false

    let settings = Prefs.shared
    private(set) var slackPID: pid_t?
    private var shownFingerprint = ""     // the conversation the suggestions belong to
    private var seenFingerprint = ""      // the conversation last read from screen
    private var settleTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?

    private var brain: Brain { Brain(settings: settings) }

    /// Pill text; nil hides the pill.
    var pillText: String? {
        if let note { return note }
        switch phase {
        case .idle: return nil
        case .thinking: return "正在想怎麼回…"
        case .ready: return "✦ \(candidates.count) 個建議  \(hotkeyLabel)"
        case .failed: return "⚠︎ 沒有產生建議  \(hotkeyLabel)"
        }
    }

    var replyTo: ChatMessage? { conversation?.messages.last { !$0.isMe } }

    // MARK: - Screen updates

    func slackLeft() {
        slackInFront = false
        panelShown = false
    }

    func update(_ convo: Conversation?, pid: pid_t) {
        slackInFront = true
        slackPID = pid
        conversation = convo
        guard let convo else { return }
        let print = Self.fingerprint(convo)
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
            self.analyze()
        }
    }

    // MARK: - Suggestions

    func analyze() {
        guard let convo = conversation else { return }
        workTask?.cancel()
        shownFingerprint = Self.fingerprint(convo)
        phase = .thinking
        candidates = []
        judgment = nil
        guard settings.hasWriterKey || !settings.typesafeKey.isEmpty else {
            phase = .failed(Brain.Failure.missingKey.localizedDescription)
            return
        }
        workTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            var picks: [String] = []
            do {
                let judgment = try await self.brain.judge(convo)
                guard !Task.isCancelled else { return }
                self.judgment = judgment
                picks = judgment.strategies.prefix(3).map(\.name)
                Log.write("judge \(Int(Date().timeIntervalSince(started) * 1000))ms intent=\(judgment.intent)")
            } catch {
                // Writing without Jev's picks still helps; the panel says Jev was skipped.
                Log.write("judge failed: \(error.localizedDescription)")
            }
            guard self.settings.hasWriterKey else {
                // A TypeSafe key alone still answers "what do they want, how soon"; writing needs an LLM.
                self.phase = .failed("Jev 判斷好了。填入 OpenRouter key，就能幫你寫回覆")
                return
            }
            do {
                let written = try await self.brain.write(convo, strategies: picks, judgment: self.judgment)
                guard !Task.isCancelled else { return }
                self.candidates = Array(written.prefix(3))
                self.phase = .ready
                Log.write("suggest \(Int(Date().timeIntervalSince(started) * 1000))ms candidates=\(written.count)")
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
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Panel

    func togglePanel() {
        panelShown ? closePanel() : openPanel()
    }

    func openPanel() {
        guard let convo = conversation else { return }
        if Self.fingerprint(convo) != shownFingerprint || phase == .idle { analyze() }
        if case .failed = phase { analyze() }
        panelShown = true
    }

    func closePanel() {
        panelShown = false
        fieldFocused = false
    }

    func insert(_ index: Int) {
        guard candidates.indices.contains(index), let pid = slackPID, let convo = conversation else { return }
        let text = candidates[index].text
        closePanel()
        Task { [weak self] in
            let outcome = await Inserter.insert(text, expectedTitle: convo.title, pid: pid)
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

    private static func fingerprint(_ convo: Conversation) -> String {
        ([convo.title, convo.isThread ? "t" : "c"] + convo.messages.suffix(4).map { "\($0.sender ?? "")|\($0.text)" })
            .joined(separator: "\u{1f}")
    }
}
