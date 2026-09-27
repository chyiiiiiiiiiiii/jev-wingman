import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

/// Click, then press the new combination. Esc cancels; plain keys are refused.
struct HotkeyRecorder: View {
    @ObservedObject var settings: Prefs
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("展開建議的快捷鍵")
                Spacer()
                Button(recording ? "請按下新的組合…（Esc 取消）" : settings.hotkey.label) { recording ? stop() : start() }
                if settings.hotkey != .standard && !recording {
                    Button("還原") { settings.hotkey = .standard }.controlSize(.small)
                }
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stop() }
            if event.keyCode == 53 { return nil }
            guard let setting = HotkeySetting(event: event) else {
                problem = "要搭配 ⌘、⌥ 或 ⌃，不然會吃掉一般打字"
                return nil
            }
            if setting != settings.hotkey && !Hotkey.isFree(setting) {
                problem = "\(setting.label) 已經被其他 App 用了，換一組試試"
                return nil
            }
            settings.hotkey = setting
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

extension SettingsView {
    /// Screen Recording only takes effect in a fresh process.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Prefs
    @ObservedObject var model: AppModel
    @State private var trusted = AXIsProcessTrusted()
    @State private var canCapture = CGPreflightScreenCaptureAccess()
    @State private var testResult = ""
    @State private var testing = false
    @State private var customModel = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let custom = "custom"

    /// Pasted keys often carry a trailing newline.
    private func trimmed(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue },
                set: { binding.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    /// A listed model shows as itself; anything else, or choosing 自訂, shows the free-text field.
    private var modelChoice: Binding<String> {
        Binding(
            get: { customModel || !Prefs.writerModels.contains { $0.id == settings.model } ? Self.custom : settings.model },
            set: { choice in
                customModel = choice == Self.custom
                if !customModel { settings.model = choice }
            })
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "已開啟「輔助使用」" : "需要開啟「輔助使用」")
                    Spacer()
                    if !trusted {
                        Button("打開系統設定") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Text("在清單裡把 Wingman 打開，這裡會自動打勾。Wingman 只讀你正在看的 Slack 對話，不會自動送出任何訊息。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("1. 讓 Wingman 讀 Slack") }

            Section {
                HStack {
                    Image(systemName: canCapture ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(canCapture ? .green : .secondary)
                    Text(canCapture ? "已開啟「螢幕錄製」" : "LINE、Telegram 需要「螢幕錄製」")
                    Spacer()
                    if !canCapture {
                        Button("打開系統設定") {
                            CGRequestScreenCaptureAccess()
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                        Button("重新啟動 Wingman") { Self.relaunch() }
                    }
                }
                Text("這兩個 App 不提供文字給其他程式讀，所以 Wingman 只截它們的視窗、在這台 Mac 上辨識文字，截圖不會上傳。開啟後要重新啟動 Wingman 才會生效。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("LINE、Telegram（選用）") }

            Section {
                SecureField("OpenRouter API key（寫回覆用，sk-or-…）", text: trimmed($settings.openRouterKey))
                if let problem = Prefs.keyProblem(settings.openRouterKey, prefix: "sk-or-") {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                SecureField("TypeSafe API key（Jev 判斷用，選填）", text: trimmed($settings.typesafeKey))
                if let problem = Prefs.keyProblem(settings.typesafeKey, prefix: "api") {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                Text("Jev 只做判斷、不會寫字，所以寫回覆需要 OpenRouter。有 TypeSafe key 時 Jev 直連 TypeSafe，沒有就透過 OpenRouter 呼叫。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("去 OpenRouter 申請 key ↗", destination: URL(string: "https://openrouter.ai/keys")!)
                    Spacer()
                    Button(testing ? "測試中…" : "測試連線") {
                        testing = true
                        Task {
                            testResult = await Brain(settings: settings, app: .slack).testConnection()
                            testing = false
                        }
                    }
                    .disabled(testing)
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).textSelection(.enabled)
                }
                Picker("寫回覆的模型", selection: modelChoice) {
                    ForEach(Prefs.writerModels, id: \.id) { Text($0.label).tag($0.id) }
                    Text("自訂…").tag(Self.custom)
                }
                if modelChoice.wrappedValue == Self.custom {
                    TextField("OpenRouter 模型 ID，例如 openai/gpt-5.4-mini", text: $settings.model)
                }
                DisclosureGroup("進階") {
                    Text("聊天內容會直接從這台 Mac 送到 OpenRouter／TypeSafe，不經過其他伺服器。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("2. 連上 AI") }

            Section {
                TextField("你在聊天 App 裡顯示的名字", text: $settings.myName)
                let senders = Array(Set(model.conversation?.messages.compactMap(\.sender) ?? [])).sorted()
                if !senders.isEmpty {
                    HStack {
                        Text("是其中一個嗎？").font(.caption).foregroundStyle(.secondary)
                        ForEach(senders, id: \.self) { name in
                            Button(name) {
                                let names = settings.myName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                if !names.contains(name) {
                                    settings.myName = (names.filter { !$0.isEmpty } + [name]).joined(separator: ", ")
                                }
                            }.controlSize(.small)
                        }
                    }
                }
                Text("用來分辨 Slack、Discord 裡哪些訊息是你說的。各 App 顯示的名字不同時，用逗號分開，例如「Yii, Yii Chen」。LINE、Telegram 看氣泡位置，不需要名字。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("3. 你是誰") }

            Section {
                HotkeyRecorder(settings: settings)
                Text("在 Slack、Discord、LINE 或 Telegram 收到訊息時，輸入框右上方會出現「✦ 3 個建議」。按 \(settings.hotkey.label) 或點它展開，按 Enter 填入 ★ 推薦的那句，或按 1、2、3 選一句，確認後自己按 Enter 送出。")
                    .font(.callout)
            } header: { Text("怎麼用") }

            Section {
                Toggle("登入 Mac 時自動開啟 Wingman", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, on in
                        do {
                            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        } catch {
                            Log.write("login item: \(error.localizedDescription)")
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                HStack {
                    Text("關掉這個視窗後 Wingman 會繼續在背景運作。要再打開設定：點選單列的泡泡圖示，或從 Launchpad／Spotlight 再開一次 Wingman。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("完成") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .frame(minHeight: 480, maxHeight: .infinity)   // a grouped Form has no height of its own
        .onReceive(tick) { _ in
            trusted = AXIsProcessTrusted()
            canCapture = CGPreflightScreenCaptureAccess()
        }
    }
}
