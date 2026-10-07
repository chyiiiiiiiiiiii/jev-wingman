import AppKit
import SwiftUI
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
    /// The draft ↑↓ has moved to and Enter types: the first while drafts come in, then ★ once Jev ranks
    /// them, unless the arrows were used first.
    @Published private(set) var selected = 0
    private var movedByHand = false
    /// Tab asks the panel to put the cursor in the direction field.
    @Published var focusField = false
    @Published var hotkeyLabel = "⌥Space"
    @Published var panelWidth: CGFloat = 480
    @Published private(set) var chatInFront = false
    /// The menu bar icon is under the notch even after moving it; settings explains how to make room.
    @Published var iconHidden = false
    private(set) var app: ChatApp = .slack

    let settings = Prefs.shared
    private(set) var chatPID: pid_t?
    private var shownFingerprint = ""     // the conversation the suggestions belong to
    private var seenFingerprint = ""      // the conversation last read from screen
    private var judgedFingerprint = ""    // the conversation `judgment` is about
    private var settleTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var generation = 0            // drafts streaming in for an older request are dropped
    private var draftedFor = ""           // the chat title the drafts on screen were written for
    private var lastRead: (title: String, messages: [ChatMessage]) = ("", [])
    /// Each chat as seen earlier this session, so messages scrolled past still count. Memory only: nothing
    /// is written to disk, and it is gone when Wingman quits.
    private var earlier: [String: [ChatMessage]] = [:]
    private var unsaved: Set<String> = []
    private var saveTask: Task<Void, Never>?

    private var brain: Brain { Brain(settings: settings, app: app) }

    /// Pill text; nil hides the pill.
    var pillText: String? {
        if let note { return note }
        switch phase {
        // Nothing to suggest yet, but this chat is being read: a quiet mark says so and is a place to click.
        case .idle: return conversation == nil ? nil : "✦ \(hotkeyLabel)"
        case .thinking: return L("正在想怎麼回…")
        case .ready:
            // A tense chat says so before the panel is opened.
            if let tension = judgment?.tension, tension >= Brain.tense {
                return L("⚠︎ 氣氛緊張 · ✦ %@ 個建議  %@", "\(candidates.count)", "\(hotkeyLabel)")
            }
            return L("✦ %@ 個建議  %@", "\(candidates.count)", "\(hotkeyLabel)")
        case .skipped: return L("這則可以不回 · %@ 仍可寫回覆", "\(hotkeyLabel)")
        case .failed: return L("⚠︎ 沒有產生建議  %@", "\(hotkeyLabel)")
        }
    }

    var replyTo: ChatMessage? { conversation?.messages.last { !$0.isMe } }

    /// The draft Jev rates highest, once ranking has come back.
    var bestIndex: Int? {
        guard candidates.contains(where: { $0.score != nil }) else { return nil }
        return candidates.indices.max { (candidates[$0].score ?? 0) < (candidates[$1].score ?? 0) }
    }

    /// Sample state for `Wingman --render`, so panel changes can be looked at before shipping.
    /// A made-up chat for `--render`, in Chinese under a Chinese interface and in English otherwise,
    /// since drafts follow the chat's language.
    func loadSample(phase: Phase, drafts: Int = 3, scored: Bool = true, note: String? = nil, tense: Bool = false) {
        let chinese = interfaceLanguage.hasPrefix("zh")
        chatInFront = true
        self.note = note
        conversation = Conversation(
            title: chinese ? "#開發" : "#dev", isThread: true,
            messages: [ChatMessage(sender: "Mia", time: chinese ? "中午 12:39" : "12:39 PM",
                                   text: chinese ? "API 文件今天來得及更新嗎？" : "Can we get the API docs updated today?")],
            draft: "", composerHandle: -1, composerFrame: CGRect(x: 0, y: 0, width: 560, height: 40))
        judgment = tense
            ? Judgment(intent: "抱怨或不滿", intentConfidence: 0.42, needsReply: 0.95, urgency: 2.1, strategies: [],
                       tension: 2.4, subtext: 0.8)
            : Judgment(intent: "催進度或要時間", intentConfidence: 0.9, needsReply: 0.9, urgency: 1.2, strategies: [],
                       tension: 0.3, subtext: 0.2)
        self.phase = phase
        if drafts > 0 {
            candidates = [
                Candidate(strategy: "給進度和時間",
                          text: chinese ? "來得及，我下午把新的欄位補上，好了跟你說"
                                        : "Yes, I'm adding the new fields this afternoon. I'll ping you when it's up.",
                          score: 0.68),
                Candidate(strategy: "答應但附條件",
                          text: chinese ? "可以，但後端的欄位要先定案，三點前給我就行"
                                        : "Should be fine, as long as the backend fields are final by 3.",
                          score: 0.21),
                Candidate(strategy: "先問清楚",
                          text: chinese ? "只改 v2 的部分，還是整份都要更新？" : "Just the v2 endpoints, or the whole doc?",
                          score: 0.11),
            ].prefix(drafts).map { scored ? $0 : Candidate(strategy: $0.strategy, text: $0.text) }
            selected = bestIndex ?? 0
        }
    }

    /// Shows what Wingman said about a made-up chat, for `--render-reel`.
    func present(_ convo: Conversation, judgment: Judgment?, candidates: [Candidate], phase: Phase, note: String? = nil) {
        chatInFront = true
        conversation = convo
        self.judgment = judgment
        self.candidates = candidates
        self.phase = phase
        self.note = note
        selected = bestIndex ?? 0
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
        guard var convo else { conversation = nil; return }
        let visible = convo.messages
        if !convo.isPost {
            let key = "\(app.rawValue)|\(convo.title)"
            if earlier[key] == nil {
                if earlier.count >= 40 { earlier.removeAll() }
                // With 記住聊天紀錄 on, a chat opened again starts from what was kept last time.
                if settings.keepHistory { earlier[key] = ChatHistory.load(key) }
            }
            let known = earlier[key] ?? []
            convo.messages = Transcript.merge(known: known, seen: visible,
                                              limit: settings.keepHistory ? ChatHistory.limit : 60)
            earlier[key] = convo.messages
            if settings.keepHistory && convo.messages != known { remember(key) }
        }
        conversation = convo
        // Only messages that came in while this chat was open count; opening it or scrolling back does not.
        let sameChat = convo.title == lastRead.title || ChatTitle.same(convo.title, lastRead.title, tolerant: app.readsPixels)
        let arrived = sameChat ? Arrivals.new(since: lastRead.messages, in: visible) : []
        // Under a post, the cursor landing in its reply box is the cue: a reply is on its way.
        let replyStarted = convo.isPost && convo.title != lastRead.title
        lastRead = (convo.title, visible)
        let print = fingerprint(convo)
        guard print != seenFingerprint else { return }
        seenFingerprint = print
        settleTask?.cancel()
        if print != shownFingerprint && !panelShown {
            workTask?.cancel()
            phase = .idle
            candidates = []
            resetSelection()
            judgment = nil
        }
        // Prefetch once the other side's message has sat still, so ⌥Space opens instantly. With
        // automatic analysis off, nothing leaves the Mac until the shortcut is pressed.
        guard arrived.contains(where: { !$0.isMe }) || replyStarted, convo.awaitingReply, !settings.paused,
              settings.autoAnalyze, !panelShown else { return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.seenFingerprint == print else { return }
            self.analyze(auto: true)
        }
    }

    /// Writes changed chats a few seconds after the last change, not on every read.
    private func remember(_ key: String) {
        unsaved.insert(key)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.settings.keepHistory else { return }
            for key in self.unsaved { ChatHistory.save(key, self.earlier[key] ?? []) }
            self.unsaved.removeAll()
        }
    }

    // MARK: - Suggestions

    /// `auto` is the prefetch on a new message: drafts are written only when Jev says a reply is
    /// expected. A draft costs 2–3 Jev calls with DeepSeek V4.1 Flash and about 35 with Claude Haiku,
    /// and chatter should not raise a pill either way.
    func analyze(auto: Bool = false) {
        guard let convo = conversation else { return }
        workTask?.cancel()
        generation += 1
        draftedFor = convo.title
        let print = fingerprint(convo)
        shownFingerprint = print
        // ⌥Space after a skipped prefetch: Jev already read this exact conversation.
        let reuseJudgment = !auto && judgment != nil && judgedFingerprint == print
        phase = .thinking
        candidates = []
        resetSelection()
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
                    Log.write("judge \(Int(Date().timeIntervalSince(started) * 1000))ms")
                } catch {
                    // Writing without Jev's picks still helps.
                    Log.write("judge failed: \(error.localizedDescription)")
                }
            }
            let picks = ReplyQuestions.picks(from: self.judgment?.strategies ?? [],
                                             tense: (self.judgment?.tension ?? 0) >= Brain.tense)
            if auto, let judgment = self.judgment, judgment.needsReply < 0.5 {
                self.phase = .skipped
                Log.write("drafts skipped needs_reply=\(String(format: "%.2f", judgment.needsReply))")
                return
            }
            guard self.settings.hasWriterKey else {
                // A TypeSafe key alone still answers "what do they want, how soon"; writing needs an LLM.
                self.phase = .failed(L("這則訊息判斷好了。填入 OpenRouter key，就能幫你寫回覆"))
                return
            }
            let current = self.generation
            do {
                let written = try await self.brain.write(convo, strategies: picks, judgment: self.judgment) { drafts in
                    await self.show(drafts, for: current)
                }
                guard !Task.isCancelled else { return }
                withAnimation(Motion.reveal) {
                    let final = Array(written.prefix(3))
                    if final.map(\.text) != self.candidates.map(\.text) { self.candidates = final }
                    self.phase = .ready
                }
                if self.panelShown { Sounds.play(.ready) }     // only when someone is waiting for them
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
        generation += 1
        draftedFor = convo.title
        let current = generation
        phase = .thinking
        candidates = []
        resetSelection()
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let written = try await self.brain.rewrite(convo, direction: direction, previous: previous) { drafts in
                    await self.show(drafts, for: current)
                }
                guard !Task.isCancelled else { return }
                withAnimation(Motion.reveal) {
                    let final = Array(written.prefix(3))
                    if final.map(\.text) != self.candidates.map(\.text) { self.candidates = final }
                    self.phase = .ready
                }
                if self.panelShown { Sounds.play(.ready) }     // only when someone is waiting for them
                self.direction = ""
                await self.rankCandidates(convo)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Drafts finished while the rest are still being written; ignored once a newer request started.
    private func show(_ drafts: [Candidate], for request: Int) {
        guard request == generation, phase == .thinking else { return }
        withAnimation(Motion.reveal) { candidates = Array(drafts.prefix(3)) }
    }

    /// Scores arrive after the drafts; numbers stay put so a key already on its way hits the draft it meant.
    private func rankCandidates(_ convo: Conversation) async {
        let drafts = candidates.map(\.text)
        guard drafts.count > 1 else { return }
        ranking = true
        defer { ranking = false }
        let started = Date()
        do {
            let scores = try await brain.rank(convo, drafts: drafts, tense: (judgment?.tension ?? 0) >= Brain.tense)
            guard !Task.isCancelled, candidates.map(\.text) == drafts else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                for index in candidates.indices { candidates[index].score = scores[index] }
                if !movedByHand, let best = bestIndex { selected = best }
            }
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

    /// Enter: the draft the arrows are on.
    func insertSelected() {
        insert(candidates.indices.contains(selected) ? selected : bestIndex ?? 0)
    }

    func moveSelection(_ step: Int) {
        guard !candidates.isEmpty else { return }
        selected = min(max(0, selected + step), candidates.count - 1)
        movedByHand = true
    }

    private func resetSelection() {
        selected = 0
        movedByHand = false
    }

    func insert(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        // Which draft people take, never its words: how often ★ is the one is the measure of the ranking.
        Log.write("pick slot=\(index + 1) best=\(index == bestIndex)")
        guard let pid = chatPID else { return }
        let text = candidates[index].text
        let app = app, chat = draftedFor
        closePanel()
        Task { [weak self] in
            let outcome = await Inserter.insert(text, app: app, expectedTitle: chat, pid: pid)
            if case .copied = outcome {} else { Sounds.play(.inserted) }
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

    /// Which chat and message the drafts answer. Reads that differ only in spacing or older lines keep it: OCR
    /// jitter used to throw away drafts written in the background and cancel Jev mid-request.
    private func fingerprint(_ convo: Conversation) -> String {
        app.rawValue + "\u{1f}" + convo.replyKey
    }
}
