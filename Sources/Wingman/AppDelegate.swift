import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panels: PanelController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var reading = false
    private var accessibilityEnabledFor: pid_t?
    private var hotkey: Hotkey?
    private let axQueue = DispatchQueue(label: "wingman.ax", qos: .userInitiated)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch trusted=\(AXIsProcessTrusted())")
        panels = PanelController(model: model)
        setUpStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        if !AXIsProcessTrusted() || !Prefs.shared.hasWriterKey || Prefs.shared.myName.isEmpty {
            showSettings()
        }
        frontmostChanged()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) brings up settings: the menu bar
    /// icon can hide behind the notch when the bar is crowded.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Watching Slack

    private func frontmostChanged() {
        if Slack.isFrontmost {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                tick()
            }
            registerHotkey()
        } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            timer?.invalidate()
            timer = nil
            hotkey = nil     // ⌥Space belongs to other apps outside Slack
            model.slackLeft()
        }
    }

    private func tick() {
        guard !reading, AXIsProcessTrusted(), let slack = Slack.running, Slack.isFrontmost else { return }
        let pid = slack.processIdentifier
        if accessibilityEnabledFor != pid {
            AXSnapshot.enableWebAccessibility(pid: pid)
            accessibilityEnabledFor = pid
        }
        reading = true
        let me = Prefs.storedMyName
        axQueue.async { [weak self] in
            let convo = Slack.read(pid: pid, myName: me)?.0
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                self.model.update(convo, pid: pid)
            }
        }
    }

    private func registerHotkey() {
        guard hotkey == nil else { return }
        let toggle: () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.model.togglePanel() }
        }
        if let key = Hotkey(keyCode: kVK_Space, modifiers: optionKey, id: 1, handler: toggle) {
            hotkey = key
            model.hotkeyLabel = "⌥Space"
        } else {
            hotkey = Hotkey(keyCode: kVK_Space, modifiers: optionKey | controlKey, id: 2, handler: toggle)
            model.hotkeyLabel = "⌃⌥Space"
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let glyph = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "Wingman")
        glyph?.isTemplate = true
        statusItem.button?.image = glyph
        let menu = NSMenu()
        let pause = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let settings = NSMenuItem(title: "設定…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "結束 Wingman", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func togglePause() {
        Prefs.shared.paused.toggle()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: Prefs.shared, model: model))
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Wingman 設定"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 540, height: 720))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.items.first?.title = Prefs.shared.paused ? "繼續提供建議" : "暫停建議"
        }
    }
}
