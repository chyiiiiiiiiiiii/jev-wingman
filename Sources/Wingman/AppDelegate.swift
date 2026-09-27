import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panels: PanelController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var timer: Timer?
    private var watching: ChatApp?
    private var askedForScreenCapture = false
    private var reading = false
    private var lastReadState = ""
    private var accessibilityEnabledFor: pid_t?
    private var hotkey: Hotkey?
    private var hotkeyObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch trusted=\(AXIsProcessTrusted()) screenCapture=\(CGPreflightScreenCaptureAccess())")
        NSApp.mainMenu = Self.mainMenu()
        panels = PanelController(model: model)
        setUpStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        model.hotkeyLabel = Prefs.shared.hotkey.label
        hotkeyObservation = Prefs.shared.$hotkey.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hotkey = nil
                self.model.hotkeyLabel = Prefs.shared.hotkey.label
                if ChatApp.frontmost != nil { self.registerHotkey() }
            }
        }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        if !Prefs.shared.onboarded {
            showOnboarding()
        } else if !AXIsProcessTrusted() || !Prefs.shared.hasWriterKey {
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
        if let front = ChatApp.frontmost {
            if watching != front.app {
                watching = front.app
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: front.app.pollInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                tick()
            }
            if front.app.readsPixels && !CGPreflightScreenCaptureAccess() && !askedForScreenCapture {
                askedForScreenCapture = true
                CGRequestScreenCaptureAccess()     // macOS shows its prompt once
            }
            if !front.app.isBrowser { registerHotkey() }     // a browser gets it once a Messenger tab is read
        } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            timer?.invalidate()
            timer = nil
            watching = nil
            hotkey = nil     // the shortcut belongs to other apps outside the chat apps
            model.chatLeft()
        }
    }

    private func tick() {
        guard !reading, AXIsProcessTrusted(), let front = ChatApp.frontmost else { return }
        if front.app.isElectron && accessibilityEnabledFor != front.pid {
            AXSnapshot.enableWebAccessibility(pid: front.pid)
            accessibilityEnabledFor = front.pid
        }
        reading = true
        let me = Prefs.storedMyName
        Task { [weak self] in
            // Readers.read is nonisolated, so the accessibility walk and OCR run off the main actor.
            let reading = await Readers.read(front.app, pid: front.pid, myName: me)
            guard let self else { return }
            self.reading = false
            let convo = reading?.conversation
            let state = convo.map { "ok messages=\($0.messages.count) last=\($0.messages.last.map { $0.isMe ? "me" : "them" } ?? "-")" }
                ?? "nothing"
            if state != self.lastReadState {    // log changes only; no message text
                self.lastReadState = state
                Log.write("read \(front.app.rawValue) \(state)")
            }
            self.model.update(convo, app: front.app, pid: front.pid)
            if front.app.isBrowser {
                if reading == nil { self.hotkey = nil } else { self.registerHotkey() }
            }
        }
    }

    private func registerHotkey() {
        guard hotkey == nil else { return }
        let setting = Prefs.shared.hotkey
        hotkey = Hotkey(keyCode: setting.keyCode, modifiers: setting.modifiers, id: 1) { [weak self] in
            MainActor.assumeIsolated { self?.model.togglePanel() }
        }
        model.hotkeyLabel = setting.label
        if hotkey == nil { Log.write("hotkey \(setting.label) is taken") }
    }

    /// A menu bar app has no menus, yet ⌘V, ⌘C and ⌘A in text fields are the Edit menu's key
    /// equivalents; without it nothing can be pasted into settings or the suggestion panel.
    private static func mainMenu() -> NSMenu {
        let edit = NSMenu(title: L("編輯"))
        edit.addItem(withTitle: L("還原"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("剪下"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷貝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("貼上"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全選"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let app = NSMenu(title: "Wingman")
        app.addItem(withTitle: L("關閉視窗"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        app.addItem(withTitle: L("結束 Wingman"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menu = NSMenu()
        for submenu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
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
        let settings = NSMenuItem(title: L("設定…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("結束 Wingman"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func togglePause() {
        Prefs.shared.paused.toggle()
    }

    private func showOnboarding() {
        let view = OnboardingView(settings: Prefs.shared) { [weak self] in
            Prefs.shared.onboarded = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = L("歡迎使用 Wingman")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: Prefs.shared, model: model))
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = L("Wingman 設定")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.delegate = self
            window.setContentSize(NSSize(width: 540, height: 720))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    /// Hand focus back to whatever was in front before settings opened; Wingman stays in the menu bar.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { NSApp.hide(nil) }
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.items.first?.title = Prefs.shared.paused ? L("繼續提供建議") : L("暫停建議")
        }
    }
}
