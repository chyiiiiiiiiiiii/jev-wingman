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
            for (state, phase, drafts) in [("ready", AppModel.Phase.ready, 3), ("thinking", .thinking, 0),
                                           ("streaming", .thinking, 1)] {
                let model = AppModel()
                model.loadSample(phase: phase, drafts: drafts)
                let view = VStack(alignment: .trailing, spacing: 16) {
                    PillView(model: model)
                    SuggestionView(model: model)
                }
                .padding(24)
                .background(Color(nsColor: backdrop))
                let file = url.appendingPathComponent("panel-\(name)-\(state).png")
                write(view, appearance: NSAppearance(named: appearance)!, to: file)
                print(file.path)
            }
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for step in 0..<3 {
                let view = OnboardingView(settings: Prefs.shared, finish: {}, initialStep: step)
                    .background(Color(nsColor: .windowBackgroundColor))
                let file = url.appendingPathComponent("onboarding-\(name)-\(step + 1).png")
                write(view, appearance: NSAppearance(named: appearance)!, to: file)
                print(file.path)
            }
        }
        return 0
    }

    private static func write(_ view: some View, appearance: NSAppearance, to file: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame.size = host.fittingSize
        // Materials need a window to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
    }
}
