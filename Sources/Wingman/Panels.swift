import AppKit
import Combine
import SwiftUI
import WingmanCore

/// Floating panels that never activate Wingman, so Slack stays the app in front.
final class FloatingPanel: NSPanel {
    var acceptsKey = false
    var onKeyDown: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Stays on the chat window's Space (joining all Spaces left it floating over empty desktops),
        // and may sit over a full-screen chat app.
        collectionBehavior = [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { acceptsKey }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown || event.type == .keyUp, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Wingman is never the active app, so the first click on a panel must count.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Keeps the pill and the suggestion panel glued above the chat app's composer.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let pill = FloatingPanel()
    private let panel = FloatingPanel()
    private var observation: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
        panel.delegate = self
        pill.contentView = ClickThroughHostingView(rootView: PillView(model: model))
        panel.acceptsKey = true
        panel.contentView = ClickThroughHostingView(rootView: SuggestionView(model: model))
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        guard model.chatInFront, let composer = model.conversation?.composerFrame, composer.width > 0 else {
            pill.orderOut(nil)
            panel.orderOut(nil)
            return
        }
        // The message box in AppKit's coordinates, and the screens the panels must stay inside.
        let box = CGRect(x: composer.minX, y: Self.appKitY(ofAXY: composer.maxY), width: composer.width,
                         height: composer.height)
        let screens = NSScreen.screens.map(\.visibleFrame)

        if model.panelShown {
            pill.orderOut(nil)
            let width = min(max(composer.width, 440), 580)
            if model.panelWidth != width { model.panelWidth = width }   // the view lays out at this width
            let height = panel.contentView!.fittingSize.height
            let frame = Placement.above(box, size: CGSize(width: width, height: height), gap: 8, screens: screens).integral
            // Touch the window only when its frame really changes, and ease a height change instead of
            // snapping; the bottom edge stays on the composer.
            if !panel.isVisible {
                panel.setFrame(frame, display: true)
                panel.alphaValue = 0
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(nil)     // the drafts have the keys, not the direction field
                NSAnimationContext.runAnimationGroup { $0.duration = 0.16; panel.animator().alphaValue = 1 }
            } else if panel.frame != frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.36, 1)
                    panel.animator().setFrame(frame, display: true)
                }
            }
        } else {
            if panel.isVisible { panel.orderOut(nil) }
            guard model.pillText != nil else {
                pill.orderOut(nil)
                return
            }
            let size = pill.contentView!.fittingSize
            pill.setFrame(Placement.pill(size, over: box, screens: screens).integral, display: true)
            pill.orderFrontRegardless()
        }
    }

    /// Like a popover: a click anywhere else (the chat, another app) puts the panel away.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            if model.panelShown { model.closePanel() }
        }
    }

    /// Inserting waits for the key's release: acting on the press left a held Return repeating into the
    /// chat after the panel closed, where Return sends.
    private var pressed: UInt16?

    private func handleKey(_ event: NSEvent) -> Bool {
        let insertKeys: Set<UInt16> = [18, 19, 20, 36, 76]
        // 1–3 pick a draft only where they type digits: under Zhuyin the same keys are ㄅ, ㄉ and ˇ, and 不 or 但
        // starting a direction typed in a draft instead.
        let letter = (18...20).contains(event.keyCode) && !event.modifierFlags.contains(.command)
            && !["1", "2", "3"].contains(event.charactersIgnoringModifiers ?? "")
        if insertKeys.contains(event.keyCode) && !letter && (!model.fieldFocused || event.modifierFlags.contains(.command)) {
            if event.type == .keyDown {
                if !event.isARepeat { pressed = event.keyCode }
                return true
            }
            guard pressed == event.keyCode else { return true }
            pressed = nil
            if event.keyCode >= 18 && event.keyCode <= 20 { model.insert(Int(event.keyCode) - 18) } else { model.insertSelected() }
            return true
        }
        guard event.type == .keyDown else { return false }
        switch event.keyCode {
        case 125 where !model.fieldFocused, 126 where !model.fieldFocused:   // ↓ ↑ move between the drafts
            model.moveSelection(event.keyCode == 125 ? 1 : -1)
            return true
        case 48 where !model.fieldFocused:         // Tab: write a direction of your own
            model.focusField = true
            return true
        case 53:  // Esc: out of the field first (clearing it if it has words), then close
            if model.fieldFocused {
                if model.direction.isEmpty { panel.makeFirstResponder(nil) } else { model.direction = "" }
            } else {
                model.closePanel()
            }
            return true
        default:
            // Typing goes to the direction field whatever key it starts with; it used to go nowhere. Returning false
            // passes the press on to the field, through the input method, so Zhuyin composes as it would anywhere.
            if !model.fieldFocused, Self.writes(event), let field = panel.contentView.flatMap(Self.textField(in:)) {
                panel.makeFirstResponder(field)
            }
            return false
        }
    }

    /// A key that writes something: no ⌘ or ⌃, and neither a control character nor one of AppKit's function keys.
    private static func writes(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty,
              let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap(textField(in:)).first
    }

    /// Accessibility frames use a top-left origin on the primary screen; AppKit uses bottom-left.
    private static func appKitY(ofAXY y: CGFloat) -> CGFloat {
        (NSScreen.screens.first?.frame.height ?? 0) - y
    }
}

// MARK: - Views

struct PillView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.pillText ?? "")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(model.phase == .skipped || model.phase == .idle ? .secondary : .primary)
            .opacity(model.phase == .idle && model.note == nil ? 0.7 : 1)
            .help(L("Wingman：按 %@ 或點這裡，幫你想回覆", "\(model.hotkeyLabel)"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .fixedSize()
            .onTapGesture { model.togglePanel() }
    }
}

/// A small quiet capsule: a coloured dot or a symbol, then a few words.
struct Tag: View {
    let text: String
    var dot: Color? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            } else if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.quaternary.opacity(0.7)))
        .fixedSize()
    }
}

/// The chat's mood, from calm to breaking off: a short green bar when all is well, a longer and redder one
/// as it heats up, and a word for where it stands. "話中有話" joins it when the message means more than it says.
struct MoodBar: View {
    let tension: Double       // 0 … 4
    let subtext: Bool

    private static let words = [L("平和"), L("留意"), L("緊張"), L("快吵架"), L("翻臉")]
    private static let colors: [Color] = [.green, .yellow, .orange, .red, .red]

    var body: some View {
        let level = min(4, max(0, Int(tension.rounded())))
        HStack(spacing: 8) {
            Text(L("氣氛")).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Self.colors[level].gradient)
                    .frame(width: 96 * max(0.1, min(1, (tension + 0.5) / 4.5)))
            }
            .frame(width: 96, height: 5)
            Text(Self.words[level]).foregroundStyle(level >= 2 ? Self.colors[level] : .secondary)
                .fontWeight(level >= 2 ? .semibold : .regular)
            if subtext {
                Text(L("話中有話"))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().strokeBorder(.orange.opacity(0.7)))
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 11.5))
        .help(L("Jev 判斷這段對話離吵架有多近：平和、留意、緊張、快吵架、翻臉"))
    }
}

struct SuggestionView: View {
    @ObservedObject var model: AppModel
    @FocusState private var fieldFocused: Bool
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
            Divider()
            HStack(spacing: 6) {
                ForEach([L("更短"), L("更委婉"), L("更正式"), L("更熱情")], id: \.self) { chip in
                    Button(chip) { model.rewrite(chip) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!rewritable)
                }
            }
            TextField(L("說說你想怎麼回，例如「跟他說週五前給」，按 Enter 重寫"), text: $model.direction)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { model.rewrite(model.direction) }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: model.panelWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .onChange(of: fieldFocused) { _, focused in model.fieldFocused = focused }
        .onChange(of: model.panelShown) { _, _ in fieldFocused = false }
        .onChange(of: model.focusField) { _, wanted in
            if wanted { fieldFocused = true; model.focusField = false }
        }
    }

    /// Chips and the direction field rewrite what is on screen; nothing to rewrite while writing.
    private var rewritable: Bool {
        switch model.phase {
        case .ready, .failed: true
        default: false
        }
    }

    /// What the keys do right now.
    private var hint: String {
        if fieldFocused { return L("Enter 重寫 · Esc 回到選項 · ⌘1–3 填入") }
        switch model.phase {
        case .ready: return L("↑↓ 選一句 · Enter 填入 · 打字說你的想法 · Esc 關閉 · 不會自動送出")
        case .failed: return L("Esc 關閉")
        default: return L("正在寫，好了就能 ↑↓ 選、Enter 填入 · Esc 關閉")
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .top) {
            headerText
            Spacer(minLength: 8)
            Button { model.closePanel() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("關閉（Esc）"))
        }
    }

    /// When to reply, as a small tag whose dot keeps the urgency colour; a globe under a public post.
    @ViewBuilder private func replyTag(_ j: Judgment) -> some View {
        if model.conversation?.isPost == true {
            // A reply under a post is public; say so before anything is typed.
            Tag(text: L("你的回覆會公開"), symbol: "globe")
        } else if let urgency = j.urgency {
            j.needsReply < 0.35 ? Tag(text: L("這則可以不回"), dot: .gray)
                                : Tag(text: Self.urgencyText(urgency), dot: Self.urgencyColor(urgency))
        }
    }

    @ViewBuilder private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let j = model.judgment {
                // What is happening, then what to do about it as a tag; the tag drops to its own line
                // rather than squeeze a long sentence.
                let sentence = Text(Self.plain(j.intent, sure: j.intentConfidence >= 0.5))
                    .font(.system(size: 13, weight: .semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { sentence; replyTag(j) }
                    VStack(alignment: .leading, spacing: 5) { sentence; replyTag(j) }
                }
                if let tension = j.tension {
                    MoodBar(tension: tension, subtext: (j.subtext ?? 0) >= Brain.meaningful)
                }
            } else {
                Text("Wingman").font(.system(size: 13, weight: .semibold))
            }
            if let replyTo = model.replyTo {
                // Every translation ends with the quoted text, so it can take the chat's own face.
                (Text(L("回覆 %@：%@", "\(replyTo.sender ?? L("對方"))", ""))
                    + Text(replyTo.text).font(Self.chatFont(for: replyTo.text, size: 12)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// One layout for every state: a status line that only changes its words, and three fixed slots in
    /// which a skeleton fades into its draft. Swapping layouts between writing and done re-created the
    /// rows (they replayed their entrance) and dropped the status line, which read as a jolt.
    @ViewBuilder private var content: some View {
        if case let .failed(reason) = model.phase {
            VStack(alignment: .leading, spacing: 6) {
                Text(reason).foregroundStyle(.red).font(.system(size: 12))
                Button(L("再試一次")) { model.analyze() }.controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(status)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(height: 14, alignment: .leading)
                    .contentTransition(.opacity)
                // A slot is as tall as what it holds: a skeleton keeps two lines' room while writing, and
                // a shorter draft settles in with an animated collapse rather than leaving a gap.
                ForEach(0..<3, id: \.self) { slot in
                    ZStack(alignment: .topLeading) {
                        if slot < model.candidates.count {
                            candidateRow(slot, model.candidates[slot]).transition(.opacity.combined(with: .offset(y: 6)))
                        } else {
                            SkeletonRow().transition(.opacity)
                                .environment(\.skeletonMoves, model.panelShown && model.phase == .thinking)
                        }
                    }
                }
            }
        }
    }

    private var status: String {
        switch model.phase {
        case .ready where model.ranking: return L("正在挑最推薦的一句…")
        case .ready:
            if let best = model.bestIndex, let score = model.candidates[best].score, score < 0.5 {
                return L("幾句都可以，挑你喜歡的語氣")
            }
            return L("★ 是最推薦的一句")
        default: return model.judgment == nil ? L("正在讀對話、判斷怎麼回…") : L("正在寫回覆…")
        }
    }

    private func candidateRow(_ index: Int, _ candidate: Candidate) -> some View {
        let best = model.bestIndex == index
        let chosen = model.selected == index
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .foregroundStyle(best ? .white : .primary)
                .background(best ? Self.brand : Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                // Fixed height: the ★ badge and the score bar arrive later without pushing the text down.
                HStack(spacing: 6) {
                    if best {
                        Text(L("★ 最推薦"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Self.brand, in: Capsule())
                    } else if let score = candidate.score, score >= 0.25 {
                        Text(L("也不錯")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if !candidate.strategy.isEmpty {
                        Text(L(candidate.strategy)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    ScoreBar(score: candidate.score ?? 0, highlighted: best)
                        .opacity(candidate.score == nil ? 0 : 1)
                }
                .frame(height: 18)
                Text(candidate.text)
                    .font(Self.chatFont(for: candidate.text, size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        // The frame follows the arrows; ★ stays on the draft Jev picked.
        .background(chosen ? Self.brand.opacity(0.12) : hovered == index ? Color.accentColor.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Self.brand.opacity(0.8) : .clear))
        .animation(.easeOut(duration: 0.12), value: chosen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .onTapGesture { model.insert(index) }
    }

    /// Drafts are typeset in their own language, whatever the interface's. With an English or Japanese
    /// interface the system font takes that language's CJK glyphs, so Chinese drafts got Japanese
    /// punctuation; the locale environment did not change that (checked in --render), a CJK face does.
    static func chatFont(for text: String, size: CGFloat) -> Font {
        switch ReplyLanguage.pick(replyTo: text, recent: []) {
        case .chinese: .custom(interfaceLanguage == "zh-Hans" ? "PingFang SC" : "PingFang TC", size: size)
        case .japanese: .custom("Hiragino Sans", size: size)
        case .korean: .custom("Apple SD Gothic Neo", size: size)
        case .theirs: .system(size: size)
        }
    }

    /// The icon's indigo, not the system accent: white text on it stays legible (about 6:1) on the
    /// dark material, where accent-coloured text on an accent-tinted row did not.
    static let brand = Color(red: 0.31, green: 0.27, blue: 0.90)

    /// Jev's score as a bar only: its probabilities run to extremes (99 / 0 / 1), and a bare "0%"
    /// beside a sensible draft reads as "wrong". The number is in the tooltip.
    private struct ScoreBar: View {
        let score: Double
        let highlighted: Bool

        var body: some View {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(highlighted ? SuggestionView.brand : Color.secondary.opacity(0.6))
                    .frame(width: max(3, 48 * score))
            }
            .frame(width: 48, height: 4)
            .help(L("推薦分數 %@%%", "\(Int((score * 100).rounded()))"))
        }
    }

    static func urgencyColor(_ urgency: Double) -> Color {
        switch urgency {
        case 2.5...: .red
        case 1.5...: .orange
        case 0.5...: .yellow
        default: .gray
        }
    }

    static func urgencyText(_ urgency: Double) -> String {
        switch urgency {
        case 2.5...: L("對方正在等，建議馬上回")
        case 1.5...: L("最好一小時內回")
        case 0.5...: L("今天內回就好")
        default: L("不急，有空再回")
        }
    }

    /// What the other side is doing, said the way a friend would whisper it; "好像" when Jev is less than sure.
    /// Jev answers with the option's name, which stays the name in code and in the writer's brief.
    static func plain(_ intent: String, sure: Bool) -> String {
        switch intent {
        case "問資訊": sure ? L("對方在問你一件事") : L("對方好像在問你一件事")
        case "請求或交辦": sure ? L("對方想請你幫忙") : L("對方好像想請你幫忙")
        case "催進度或要時間": sure ? L("對方在等你的進度") : L("對方好像在等你的進度")
        case "確認或同意": sure ? L("對方在等你點頭") : L("對方好像在等你點頭")
        case "告知": sure ? L("對方在跟你說一件事") : L("對方好像在跟你說一件事")
        case "閒聊": sure ? L("對方在閒聊") : L("對方好像在閒聊")
        case "抱怨或不滿": sure ? L("對方有點不滿") : L("對方好像有點不滿")
        case "感謝或稱讚": sure ? L("對方在謝謝你") : L("對方好像在謝謝你")
        case "分享觀點": sure ? L("對方在分享看法") : L("對方好像在分享看法")
        case "分享生活或成果": sure ? L("對方在分享近況") : L("對方好像在分享近況")
        case "提問或求助": sure ? L("對方在找答案") : L("對方好像在找答案")
        case "徵求互動": sure ? L("對方想聽大家的想法") : L("對方好像想聽大家的想法")
        case "宣傳或公告": sure ? L("對方在宣傳或公告") : L("對方好像在宣傳或公告")
        case "心情抒發": sure ? L("對方在抒發心情") : L("對方好像在抒發心情")
        case "幽默或玩梗": sure ? L("對方在搞笑") : L("對方好像在搞笑")
        default: L(intent)
        }
    }
}
