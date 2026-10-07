import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panels: PanelController!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var timer: Timer?
    private var watching: Front?
    private var askedForScreenCapture = false
    private var reading = false
    private var lastReadState = ""
    private var accessibilityEnabledFor: pid_t?
    private var hotkey: Hotkey?
    private var hotkeyObservation: AnyCancellable?
    private var appsObservation: AnyCancellable?
    private var pauseObservation: AnyCancellable?
    private static let statusTag = 1, pauseTag = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch trusted=\(AXIsProcessTrusted()) screenCapture=\(CGPreflightScreenCaptureAccess())")
        NSApp.mainMenu = Self.mainMenu()
        panels = PanelController(model: model)
        Sounds.prepare()
        ChatHistory.forgetStale()
        setUpStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        pickFreeHotkey()
        model.hotkeyLabel = Prefs.shared.hotkey.label
        hotkeyObservation = Prefs.shared.$hotkey.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hotkey = nil
                self.model.hotkeyLabel = Prefs.shared.hotkey.label
                // A browser's comes with a web chat tab; in settings it is there to be tried out.
                if Front.current?.app != nil || NSApp.isActive { self.registerHotkey() }
            }
        }
        appsObservation = Prefs.shared.$disabledApps.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.watching = nil
                self?.hotkey = nil
                self?.model.chatLeft()
                self?.frontmostChanged()
            }
        }
        // Paused, the icon fades, so a Wingman that stopped suggesting on purpose does not look broken.
        pauseObservation = Prefs.shared.$paused.sink { [weak self] paused in
            DispatchQueue.main.async { self?.statusItem?.button?.appearsDisabled = paused }
        }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.keepIconInSight() }
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

    // MARK: - Watching the chat in front

    private func frontmostChanged() {
        if let front = Front.current {
            if watching != front {
                watching = front
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: front.pollInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                tick()
            }
            if front.app?.readsPixels == true && !CGPreflightScreenCaptureAccess() && !askedForScreenCapture {
                askedForScreenCapture = true
                CGRequestScreenCaptureAccess()     // macOS shows its prompt once
            }
            if front.app != nil { registerHotkey() }     // a browser gets it once a web chat tab is read
        } else if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            timer?.invalidate()
            timer = nil
            watching = nil
            hotkey = nil     // the shortcut belongs to other apps outside the chat apps
            model.chatLeft()
        }
    }

    private func tick() {
        guard !reading, AXIsProcessTrusted(), let front = Front.current else { return }
        if front.app?.isElectron == true && accessibilityEnabledFor != front.pid {
            AXSnapshot.enableWebAccessibility(pid: front.pid)
            accessibilityEnabledFor = front.pid
        }
        reading = true
        let me = Prefs.storedMyName
        Task { [weak self] in
            // Readers.read is nonisolated, so the accessibility walk and OCR run off the main actor.
            let read = await Readers.read(front, myName: me)
            guard let self else { return }
            self.reading = false
            // A browser tab that is not a web chat leaves the app as it was, so nothing restarts.
            let app = read?.app ?? front.app ?? self.model.app
            let convo = read?.reading.conversation
            let state = convo.map { "ok messages=\($0.messages.count) last=\($0.messages.last.map { $0.isMe ? "me" : "them" } ?? "-")" }
                ?? "nothing"
            if state != self.lastReadState {    // log changes only; no message text
                self.lastReadState = state
                Log.write("read \(app.rawValue) \(state)")
            }
            self.model.update(convo, app: app, pid: front.pid)
            if case .browser = front {
                if read == nil { self.hotkey = nil } else { self.registerHotkey() }
            }
        }
    }

    private func registerHotkey() {
        guard hotkey == nil else { return }
        let setting = Prefs.shared.hotkey
        hotkey = Hotkey(keyCode: setting.keyCode, modifiers: setting.modifiers, id: 1) { [weak self] in
            MainActor.assumeIsolated {
                // Pressed in Wingman's own settings, the shortcut is only being tried out.
                guard !NSApp.isActive else { return }
                self?.model.togglePanel()
            }
        }
        model.hotkeyLabel = setting.label
        if hotkey == nil { Log.write("hotkey \(setting.label) is taken") }
    }

    /// A first shortcut nobody else answers. Carbon cannot tell: Raycast holding ⌥Space still let Wingman register
    /// it, and the press opened Raycast. Only a shortcut never chosen is changed.
    private func pickFreeHotkey() {
        guard UserDefaults.standard.object(forKey: "hotkey") == nil, let owner = HotkeySetting.standard.owner,
              let free = HotkeySetting.alternatives.first(where: { $0.owner == nil }) else { return }
        Prefs.shared.hotkey = free
        Log.write("hotkey \(HotkeySetting.standard.label) belongs to \(owner); using \(free.label)")
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
        // A new icon lands at the far left of the others, under the notch on a crowded bar: start it on the
        // right. Once someone drags it, macOS saves their place under the same key and this leaves it alone.
        if UserDefaults.standard.object(forKey: MenuBarIcon.positionKey) == nil {
            UserDefaults.standard.set(MenuBarIcon.visiblePosition, forKey: MenuBarIcon.positionKey)
        }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        statusItem.autosaveName = MenuBarIcon.name
        let glyph = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "Wingman")
        glyph?.isTemplate = true
        statusItem.button?.image = glyph
        statusItem.button?.appearsDisabled = Prefs.shared.paused
        let menu = NSMenu()
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.tag = Self.statusTag
        menu.addItem(status)
        menu.addItem(.separator())
        let pause = NSMenuItem(title: "", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.tag = Self.pauseTag
        menu.addItem(pause)
        let settings = NSMenuItem(title: L("設定…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("結束 Wingman"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    /// An icon under the notch cannot be clicked. Move it to the right side once per launch; if it is still
    /// covered (the right side is full too), settings says so and how to make room.
    private func keepIconInSight() {
        guard let old = statusItem, MenuBarIcon.isHidden(old) else { return }
        Log.write("menu bar icon was under the notch; moving it right")
        // Releasing the old icon clears its saved place, so it must be gone before the new place is written.
        NSStatusBar.system.removeStatusItem(old)
        statusItem = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            UserDefaults.standard.set(MenuBarIcon.visiblePosition, forKey: MenuBarIcon.positionKey)
            self?.setUpStatusItem()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let item = self.statusItem else { return }
                self.model.iconHidden = MenuBarIcon.isHidden(item)
                Log.write("menu bar icon \(self.model.iconHidden ? "still hidden" : "in sight")")
            }
        }
    }

    /// What Wingman can see right now, at the top of its menu: the answer to "why is nothing happening?". `fixable`
    /// when settings can fix it, which a click on the line then opens.
    private func statusLine() -> (text: String, fixable: Bool) {
        guard AXIsProcessTrusted() else { return (L("⚠︎ 還沒開啟「輔助使用」，讀不到聊天"), true) }
        if let owner = Prefs.shared.hotkey.owner {
            return (L("⚠︎ %@ 也用 %@，按下去可能會打開它", owner, Prefs.shared.hotkey.label), true)
        }
        guard model.chatInFront else { return (L("打開聊天 App，Wingman 就會開始讀"), false) }
        let app = model.app
        if app.readsPixels && !CGPreflightScreenCaptureAccess() {
            return (L("%@ 需要「螢幕與系統錄音」才讀得到", app.name), true)
        }
        guard let convo = model.conversation else { return (L("%@：這個畫面讀不到對話", app.name), false) }
        if Prefs.shared.paused { return (L("已暫停自動分析，按 %@ 仍可用", model.hotkeyLabel), false) }
        return (L("%@：正在看「%@」", app.name, convo.title), false)
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
        registerHotkey()     // to be tried out on the last step
    }

    @objc func showSettings() {
        model.iconHidden = statusItem.map(MenuBarIcon.isHidden) ?? false
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
        registerHotkey()     // to be tried out beside the shortcut recorder
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    /// Hand focus back to whatever was in front before settings opened; Wingman stays in the menu bar.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.hide(nil)
            // Settings checks permissions once a second; a window kept after closing went on checking for good.
            DispatchQueue.main.async { self.settingsWindow = nil }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.item(withTag: Self.pauseTag)?.title = Prefs.shared.paused ? L("繼續提供建議") : L("暫停建議")
            if let status = menu.item(withTag: Self.statusTag) {
                let line = statusLine()
                status.title = line.text
                status.action = line.fixable ? #selector(showSettings) : nil
                status.target = line.fixable ? self : nil
            }
        }
    }
}
