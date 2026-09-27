import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI
import WingmanCore

/// Click, then press the new combination. Esc cancels; plain keys are refused.
/// A setting's name and, under it, what it is for in one plain sentence.
struct SettingPurpose: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

/// Pasted keys often carry a trailing newline.
func trimmedKey(_ binding: Binding<String>) -> Binding<String> {
    Binding(get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines) })
}

struct HotkeyRecorder: View {
    @ObservedObject var settings: Prefs
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("展開建議的快捷鍵"))
                Spacer()
                Button(recording ? L("請按下新的組合…（Esc 取消）") : settings.hotkey.label) { recording ? stop() : start() }
                if settings.hotkey != .standard && !recording {
                    Button(L("恢復預設")) { settings.hotkey = .standard }.controlSize(.small)
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
                problem = L("要搭配 ⌘、⌥ 或 ⌃，不然會吃掉一般打字")
                return nil
            }
            if setting != settings.hotkey && !Hotkey.isFree(setting) {
                problem = L("%@ 已經被其他 App 用了，換一組試試", "\(setting.label)")
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
    @State private var confirmErase = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var systemSounds = Sounds.systemAllowsThem
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let custom = "custom"

    private func appEnabled(_ app: ChatApp) -> Binding<Bool> {
        Binding(get: { !settings.disabledApps.contains(app.rawValue) },
                set: { on in
                    if on { settings.disabledApps.remove(app.rawValue) } else { settings.disabledApps.insert(app.rawValue) }
                })
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

    /// Both sounds of a voice, one after the other.
    private func preview(_ voice: Chime.Voice) {
        Sounds.play(voice, .ready)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Sounds.play(voice, .inserted) }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? L("已開啟「輔助使用」") : L("需要開啟「輔助使用」"))
                    Spacer()
                    if !trusted {
                        Button(L("打開系統設定")) {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Text(L("用來讀 Slack、Discord，以及 Messenger、Instagram、Threads 網頁版的對話，並把你選的回覆填進輸入框。瀏覽器裡只讀這三個網站的訊息頁，其他網頁不讀。在清單裡把 Wingman 打開，這裡會自動打勾。Wingman 只讀你正在看的對話，不會自動送出任何訊息。"))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L("1. 讓 Wingman 讀聊天內容")) }

            Section {
                HStack {
                    Image(systemName: canCapture ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(canCapture ? .green : .secondary)
                    Text(canCapture ? L("已開啟「螢幕與系統錄音」") : L("LINE、Telegram 需要「螢幕與系統錄音」"))
                    Spacer()
                    if !canCapture {
                        Button(L("打開系統設定")) {
                            CGRequestScreenCaptureAccess()
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                        Button(L("重新啟動 Wingman")) { Self.relaunch() }
                    }
                }
                Text(L("這兩個 App 不提供文字給其他程式讀，所以 Wingman 只截它們的視窗、在這台 Mac 上辨識文字，截圖不會上傳。開啟後要重新啟動 Wingman 才會生效。"))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L("LINE、Telegram（選用）")) }

            Section {
                SettingPurpose(L("寫回覆：OpenRouter（必填）"),
                        L("請 AI 寫出 3 句候選回覆。按用量付費，要先在 OpenRouter 儲值（例如 US$5）；一次建議大約 US$0.0002。"))
                SecureField("OpenRouter API key（sk-or-v1-…）", text: trimmedKey($settings.openRouterKey))
                if let problem = Prefs.keyProblem(settings.openRouterKey, prefix: "sk-or-") {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                HStack(spacing: 16) {
                    Link(L("申請 key ↗"), destination: URL(string: "https://openrouter.ai/keys")!)
                    Link(L("儲值 ↗"), destination: URL(string: "https://openrouter.ai/settings/credits")!)
                }
                .font(.callout)

                SettingPurpose(L("判斷訊息：TypeSafe 的 Jev（選填）"),
                        L("判斷對方想要什麼、需不需要回、有多急，並從 3 句裡挑出最推薦的那句。沒填也能用，會改透過 OpenRouter 呼叫，每次建議大約慢 2–4 秒。"))
                SecureField("TypeSafe API key", text: trimmedKey($settings.typesafeKey))
                if let problem = Prefs.keyProblem(settings.typesafeKey, prefix: "api") {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
                Link(L("申請 key ↗"), destination: URL(string: "https://console.typesafe.ai/keys")!)
                    .font(.callout)

                Picker(L("寫回覆的模型"), selection: modelChoice) {
                    ForEach(Prefs.writerModels, id: \.id) { Text($0.name).tag($0.id) }
                    Text(L("自訂…")).tag(Self.custom)
                }
                if modelChoice.wrappedValue == Self.custom {
                    TextField(L("OpenRouter 模型 ID，例如 openai/gpt-5.4-mini"), text: $settings.model)
                }
                Text(Prefs.writerModels.first { $0.id == settings.model }?.note ?? L("用任何 OpenRouter 上的模型。"))
                    .font(.caption).foregroundStyle(.secondary)

                HStack(alignment: .top) {
                    Text(testResult.isEmpty ? L("填好 key 後按「測試連線」，確認都能用。") : testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                    Spacer()
                    Button(testing ? L("測試中…") : L("測試連線")) {
                        testing = true
                        Task {
                            testResult = await Brain(settings: settings, app: .slack).testConnection()
                            testing = false
                        }
                    }
                    .disabled(testing)
                }
                Label(L("key 只存在這台 Mac 的鑰匙圈，只會送到它所屬的服務。"),
                      systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L("2. 連上 AI")) }

            Section {
                TextField(L("你在聊天 App 裡顯示的名字"), text: $settings.myName)
                Text(L("用來分辨 Slack、Discord 裡哪些訊息是你說的。各 App 顯示的名字不同時，用逗號分開，例如「Yii, Yii Chen」。LINE、Telegram 和網頁版的 Messenger、Instagram、Threads 看氣泡位置，不需要名字。"))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L("3. 你是誰")) }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Wingman 沒有自己的伺服器，開發者收不到你的 key，也收不到聊天內容。")).fontWeight(.semibold)
                    Text(L("送出去的只有你正在看的對話裡最近 20 則訊息、聊天室名稱和發言人名字：判斷送到 TypeSafe（承諾不拿來訓練模型），寫回覆送到 OpenRouter，而且只轉給不保留、不訓練的供應商。聊天內容不會存在這台 Mac 上，紀錄檔只記時間、次數和花費。"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Link(L("OpenRouter 隱私政策 ↗"), destination: URL(string: "https://openrouter.ai/privacy")!)
                        Link(L("TypeSafe 隱私政策 ↗"), destination: URL(string: "https://typesafe.ai/legal/privacy-policy")!)
                    }
                    .font(.callout)
                }
                Toggle(isOn: $settings.autoAnalyze) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("新訊息進來時自動分析"))
                        Text(L("關掉後，只有你按快捷鍵時才會把對話送出去。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("在這些 App 使用 Wingman"))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
                              alignment: .leading, spacing: 6) {
                        ForEach(ChatApp.allCases, id: \.self) { app in
                            Toggle(app.name, isOn: appEnabled(app)).toggleStyle(.checkbox)
                        }
                    }
                    Text(L("沒勾的 App，Wingman 完全不會讀取。")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L("清除 Wingman 的所有資料…"), role: .destructive) { confirmErase = true }
                }
            } header: { Text(L("隱私與控制")) }
            .alert(L("清除所有資料？"), isPresented: $confirmErase) {
                Button(L("清除並重新啟動"), role: .destructive) {
                    Prefs.eraseEverything()
                    Self.relaunch()
                }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("會刪除鑰匙圈裡的 key、所有設定和紀錄檔，然後重新啟動 Wingman。聊天內容本來就不會存在這台 Mac 上。"))
            }

            Section {
                HotkeyRecorder(settings: settings)
                Text(L("在 Slack、Discord、LINE、Telegram，或 Messenger、Instagram、Threads 網頁版收到訊息時，輸入框右上方會出現「✦ 3 個建議」。按 %@ 或點它展開，按 Enter 填入 ★ 推薦的那句，或按 1、2、3 選一句，確認後自己按 Enter 送出。", "\(settings.hotkey.label)"))
                    .font(.callout)
            } header: { Text(L("怎麼用")) }

            Section {
                Toggle(isOn: $settings.soundsOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("互動音效"))
                        Text(L("你在等的建議寫好時，和回覆填進輸入框時，輕輕響一聲。背景自動分析完成時不會出聲。音量跟著系統的提示音音量。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Picker(L("音色"), selection: $settings.soundVoice) {
                        ForEach(Chime.Voice.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button(L("試聽")) { preview(settings.soundVoice) }
                }
                .disabled(!settings.soundsOn)
                .onChange(of: settings.soundVoice) { _, voice in preview(voice) }
                if settings.soundsOn && !systemSounds {
                    HStack {
                        Text(L("系統設定裡的「播放使用者介面音效」是關的，所以不會出聲。"))
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(L("打開系統設定")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                        }
                        .controlSize(.small)
                    }
                }
            } header: { Text(L("音效")) }

            Section {
                Toggle(isOn: $opensAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("登入 Mac 時自動開啟 Wingman"))
                        Text(L("開機後就在背景待命，平常不用自己打開。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                    .onChange(of: opensAtLogin) { _, on in
                        do {
                            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        } catch {
                            Log.write("login item: \(error.localizedDescription)")
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                HStack {
                    Text(L("關掉這個視窗後 Wingman 會繼續在背景運作。要再打開設定：點選單列的泡泡圖示，或從 Launchpad／Spotlight 再開一次 Wingman。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("完成")) { NSApp.keyWindow?.performClose(nil) }
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
            systemSounds = Sounds.systemAllowsThem
        }
    }
}
