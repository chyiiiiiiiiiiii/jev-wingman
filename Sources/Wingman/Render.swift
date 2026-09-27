import AppKit
import SwiftUI
import WingmanCore

/// `Wingman --render <dir>`: draws the pill and the suggestion panel with sample data, light and dark,
/// over a chat-like backdrop, so a change can be looked at as pixels before it ships.
@MainActor
enum Render {
    static func run(to directory: String) -> Int32 {
        Prefs.usesKeychain = false
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, appearance, backdrop) in [("light", NSAppearance.Name.aqua, NSColor(white: 0.96, alpha: 1)),
                                             ("dark", .darkAqua, NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1))] {
            for (state, phase, drafts, scored) in [("1-thinking", AppModel.Phase.thinking, 0, false),
                                                   ("2-streaming", .thinking, 1, false),
                                                   ("3-written", .ready, 3, false),
                                                   ("4-ranked", .ready, 3, true)] {
                let model = AppModel()
                model.loadSample(phase: phase, drafts: drafts, scored: scored)
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
        let settings = SettingsView(settings: Prefs.shared, model: AppModel())
            .frame(height: 1180)
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
