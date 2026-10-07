import AppKit
import SwiftUI
import WingmanCore

/// `Wingman --render <dir>`: draws the pill and the suggestion panel with sample data, light and dark,
/// over a chat-like backdrop, so a change can be looked at as pixels before it ships. The sounds are
/// written beside them as WAV files, to be listened to the same way.
@MainActor
enum Render {
    static func run(to directory: String) -> Int32 {
        Prefs.usesKeychain = false
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, appearance, backdrop) in [("light", NSAppearance.Name.aqua, NSColor(white: 0.96, alpha: 1)),
                                             ("dark", .darkAqua, NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1))] {
            for (state, phase, drafts, scored, tense) in [("1-thinking", AppModel.Phase.thinking, 0, false, false),
                                                          ("2-streaming", .thinking, 1, false, false),
                                                          ("3-written", .ready, 3, false, false),
                                                          ("4-ranked", .ready, 3, true, false),
                                                          ("5-tense", .ready, 3, true, true),
                                                          ("6-no-credit", .failed(Brain.Failure.http(402, "").localizedDescription,
                                                                                  .credits), 0, false, false),
                                                          ("7-no-key", .failed(Brain.Failure.missingKey.localizedDescription,
                                                                               .settings), 0, false, false)] {
                let model = AppModel()
                model.loadSample(phase: phase, drafts: drafts, scored: scored, tense: tense)
                let view = VStack(alignment: .trailing, spacing: 16) {
                    PillView(model: model)
                    SuggestionView(model: model)
                }
                .padding(24)
                .background(Color(nsColor: backdrop))
                let file = url.appendingPathComponent("panel-\(name)-\(state).png")
                let height = write(view, appearance: NSAppearance(named: appearance)!, to: file)
                print("\(file.lastPathComponent) height \(Int(height))")
            }
        }
        // The one-time note over the first chat after the shortcut was moved off a taken ⌥Space.
        let moved = AppModel()
        moved.loadSample(phase: .idle, drafts: 0,
                         note: L("快捷鍵改成 %@（%@ 被 %@ 用了）", "⌥⇧Space", HotkeySetting.standard.label, "Raycast"))
        write(PillView(model: moved).padding(24).background(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1))),
              appearance: NSAppearance(named: .darkAqua)!, to: url.appendingPathComponent("pill-hotkey-moved.png"))
        let settings = SettingsView(settings: Prefs.shared, model: AppModel())
            .frame(height: 1900)
            .background(Color(nsColor: .windowBackgroundColor))
        write(settings, appearance: NSAppearance(named: .darkAqua)!, to: url.appendingPathComponent("settings-dark.png"))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for step in 0..<3 {
                let view = OnboardingView(settings: Prefs.shared, finish: {}, initialStep: step)
                    .background(Color(nsColor: .windowBackgroundColor))
                let file = url.appendingPathComponent("onboarding-\(name)-\(step + 1).png")
                let height = write(view, appearance: NSAppearance(named: appearance)!, to: file)
                print("\(file.lastPathComponent) height \(Int(height))")
            }
        }
        for voice in Chime.Voice.allCases {
            for event in Chime.Event.allCases {
                try? Chime.wav(Chime.samples(voice, event)).write(to: url.appendingPathComponent("sound-\(voice.rawValue)-\(event).wav"))
            }
        }
        return 0
    }

    @discardableResult
    private static func write(_ view: some View, appearance: NSAppearance, to file: URL) -> CGFloat {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame.size = host.fittingSize
        // Materials need a window to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return host.frame.height }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
        return host.frame.height
    }
}

// MARK: - The README's demo

extension Render {
    /// `Wingman --render-demo <dir>`: the moments of one suggestion as frames, and `frames.txt` with how long
    /// each is held; scripts/make-demo.sh strings them into the README's GIF. The chat is made up.
    static func demo(to directory: String) -> Int32 {
        Prefs.usesKeychain = false
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let dark = NSAppearance(named: .darkAqua)!
        let best = { () -> String in
            let model = AppModel()
            model.loadSample(phase: .ready)
            return model.candidates[model.bestIndex ?? 0].text
        }()
        let beats: [(scene: DemoScene, seconds: Double)] = [
            (DemoScene(), 0.9),
            (DemoScene(arrived: true, pill: true), 1.2),
            (DemoScene(arrived: true, phase: .thinking, drafts: 0, key: "⌥ Space"), 0.9),
            (DemoScene(arrived: true, phase: .thinking, drafts: 1), 0.7),
            (DemoScene(arrived: true, phase: .ready, drafts: 3), 0.8),
            (DemoScene(arrived: true, phase: .ready, drafts: 3, scored: true), 1.8),
            (DemoScene(arrived: true, phase: .ready, drafts: 3, scored: true, key: "↩ Enter"), 0.6),
            (DemoScene(arrived: true, typed: best, note: L("已填入，檢查後按 Enter 送出")), 2.6),
        ]
        var timing = ""
        for (index, beat) in beats.enumerated() {
            let name = String(format: "frame-%02d.png", index + 1)
            write(beat.scene, appearance: dark, to: url.appendingPathComponent(name))
            timing += "\(name) \(beat.seconds)\n"
        }
        try? timing.write(to: url.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
        print("\(beats.count) frames in \(url.path)")
        return 0
    }
}

/// A made-up chat window (no real app's look) with Wingman's pill or panel over it, as they sit on screen:
/// the pill at the message box's top right, the panel resting on the box's top edge.
private struct DemoScene: View {
    var arrived = false
    var pill = false
    var phase: AppModel.Phase? = nil
    var drafts = 3
    var scored = false
    var typed: String? = nil
    var note: String? = nil
    var key: String? = nil

    private var chinese: Bool { interfaceLanguage.hasPrefix("zh") }
    private var model: AppModel {
        let model = AppModel()
        model.panelWidth = 520
        model.hotkeyLabel = "⌥Space"
        model.loadSample(phase: phase ?? .idle, drafts: phase == nil ? 0 : drafts, scored: scored, note: note)
        return model
    }

    var body: some View {
        let model = model
        VStack(spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                window
                if phase != nil {
                    SuggestionView(model: model)
                        .padding(.leading, 20)
                        .padding(.bottom, 68)
                } else if pill || note != nil {
                    HStack { Spacer(); PillView(model: model) }
                        .padding(.trailing, 30)
                        .padding(.bottom, 70)
                }
            }
            .frame(width: 840, height: 660)
            keycap
        }
        .padding(30)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .environment(\.colorScheme, .dark)
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.75)).frame(width: 12, height: 12) }
                Text(chinese ? "# 開發" : "# dev").font(.system(size: 15, weight: .semibold)).padding(.leading, 12)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 48)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                message("Leo", Color.teal, chinese ? "中午 12:31" : "12:31 PM",
                        chinese ? "部署好了，staging 看起來沒問題 👍" : "Deploy is done, staging looks good 👍")
                if arrived {
                    message("Mia", Color.purple, chinese ? "中午 12:39" : "12:39 PM",
                            chinese ? "API 文件今天來得及更新嗎？" : "Can we get the API docs updated today?")
                }
            }
            .padding(20)
            Spacer()
            HStack(spacing: 0) {
                Text(typed ?? (chinese ? "傳訊息到 # 開發" : "Message # dev"))
                    .foregroundStyle(typed == nil ? .secondary : .primary)
                if typed != nil { Rectangle().fill(.primary).frame(width: 1.5, height: 17).padding(.leading, 1) }
                Spacer()
            }
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.18)))
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.12, green: 0.12, blue: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1)))
    }

    private func message(_ name: String, _ tint: Color, _ time: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.8)).frame(width: 36, height: 36)
                .overlay(Text(String(name.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 14, weight: .bold))
                    Text(time).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(text).font(.system(size: 14))
            }
        }
    }

    /// The key being pressed, the way screencasts show it; blank space otherwise so frames line up.
    private var keycap: some View {
        Text(key ?? " ")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(key == nil ? 0 : 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(key == nil ? 0 : 0.25)))
            .frame(height: 36)
    }
}
