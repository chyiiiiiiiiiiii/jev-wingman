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
        if event.type == .keyDown, onKeyDown?(event) == true { return }
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
        let top = Self.appKitY(ofAXY: composer.minY)

        if model.panelShown {
            pill.orderOut(nil)
            let width = min(max(composer.width, 440), 580)
            if model.panelWidth != width { model.panelWidth = width }   // the view lays out at this width
            let height = panel.contentView!.fittingSize.height
            panel.setFrame(NSRect(x: composer.minX, y: top + 8, width: width, height: height), display: true)
            if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        } else {
            if panel.isVisible { panel.orderOut(nil) }
            guard model.pillText != nil else {
                pill.orderOut(nil)
                return
            }
            let size = pill.contentView!.fittingSize
            pill.setFrame(NSRect(x: composer.maxX - size.width - 10, y: top + 6, width: size.width, height: size.height),
                          display: true)
            pill.orderFrontRegardless()
        }
    }

    /// Like a popover: a click anywhere else (the chat, another app) puts the panel away.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            if model.panelShown { model.closePanel() }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53:  // Esc
            if model.fieldFocused && !model.direction.isEmpty {
                model.direction = ""
            } else {
                model.closePanel()
            }
            return true
        case 18...20 where command || !model.fieldFocused:  // 1 2 3
            model.insert(Int(event.keyCode) - 18)
            return true
        case 36 where !model.fieldFocused, 76 where !model.fieldFocused:  // Return, Enter: the recommended draft
            model.insertBest()
            return true
        default:
            return false
        }
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
            .help("Wingman：按 \(model.hotkeyLabel) 或點這裡，幫你想回覆")
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .fixedSize()
            .onTapGesture { model.togglePanel() }
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
                ForEach(["更短", "更委婉", "更正式", "更熱情"], id: \.self) { chip in
                    Button(chip) { model.rewrite(chip) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!rewritable)
                }
            }
            TextField("說說你想怎麼回，例如「跟他說週五前給」，按 Enter 重寫", text: $model.direction)
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
        .onChange(of: model.panelShown) { _, shown in if !shown { fieldFocused = false } }
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
        if fieldFocused { return "Enter 重寫 · ⌘1–3 填入 · Esc 清除" }
        switch model.phase {
        case .ready: return "Enter 填入 ★ 推薦 · 1–3 選一句 · Esc 關閉 · 不會自動送出"
        case .failed: return "Esc 關閉"
        default: return "正在寫，好了就能按 Enter 或 1–3 填入 · Esc 關閉"
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
            .help("關閉（Esc）")
        }
    }

    @ViewBuilder private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let j = model.judgment {
                HStack(spacing: 6) {
                    Circle().fill(Self.urgencyColor(j.urgency)).frame(width: 8, height: 8)
                    Text(j.intent).fontWeight(.semibold)
                    Text("·").foregroundStyle(.secondary)
                    Text(j.needsReply < 0.35 ? "可以不回" : Self.urgencyText(j.urgency)).foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
            } else {
                Text("Wingman").font(.system(size: 13, weight: .semibold))
            }
            if let replyTo = model.replyTo {
                Text("回覆 \(replyTo.sender ?? "對方")：\(replyTo.text)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .thinking, .skipped:
            // Drafts appear as they are written; skeleton rows hold the rest of the space so the
            // panel keeps its height.
            VStack(alignment: .leading, spacing: 4) {
                Text(model.judgment == nil ? "正在讀對話、判斷怎麼回…" : "正在寫回覆…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                    candidateRow(index, candidate).transition(Motion.arrival(0))
                }
                ForEach(0..<max(0, 3 - model.candidates.count), id: \.self) { _ in SkeletonRow() }
            }
        case let .failed(reason):
            VStack(alignment: .leading, spacing: 6) {
                Text(reason).foregroundStyle(.red).font(.system(size: 12))
                Button("再試一次") { model.analyze() }.controlSize(.small)
            }
        case .ready:
            VStack(alignment: .leading, spacing: 4) {
                if let best = model.bestIndex, let score = model.candidates[best].score, score < 0.5 {
                    Text("幾句都可以，挑你喜歡的語氣").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                    candidateRow(index, candidate)
                        .transition(Motion.arrival(index))
                }
            }
        }
    }

    private func candidateRow(_ index: Int, _ candidate: Candidate) -> some View {
        let best = model.bestIndex == index
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .foregroundStyle(best ? .white : .primary)
                .background(best ? Self.brand : Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if best {
                        Text("★ 最推薦")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Self.brand, in: Capsule())
                    } else if let score = candidate.score, score >= 0.25 {
                        Text("也不錯").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if !candidate.strategy.isEmpty {
                        Text(candidate.strategy).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let score = candidate.score {
                        ScoreBar(score: score, highlighted: best)
                    } else if model.ranking {
                        Text("評分中…").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                Text(candidate.text)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(best ? Self.brand.opacity(0.12) : hovered == index ? Color.accentColor.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(best ? Self.brand.opacity(0.8) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .onTapGesture { model.insert(index) }
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
            .help("推薦分數 \(Int((score * 100).rounded()))%")
        }
    }

    private static func urgencyColor(_ urgency: Double) -> Color {
        switch urgency {
        case 2.5...: .red
        case 1.5...: .orange
        case 0.5...: .yellow
        default: .gray
        }
    }

    private static func urgencyText(_ urgency: Double) -> String {
        switch urgency {
        case 2.5...: "對方正在等，建議馬上回"
        case 1.5...: "最好一小時內回"
        case 0.5...: "今天內回就好"
        default: "不急"
        }
    }
}
