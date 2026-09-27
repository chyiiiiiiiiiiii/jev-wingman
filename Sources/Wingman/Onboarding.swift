import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// First launch: three steps, one job each, and 下一步 only once that job is done.
struct OnboardingView: View {
    @ObservedObject var settings: Prefs
    var finish: () -> Void
    @State private var step: Int

    init(settings: Prefs, finish: @escaping () -> Void, initialStep: Int = 0) {
        self.settings = settings
        self.finish = finish
        _step = State(initialValue: initialStep)
    }
    @State private var trusted = AXIsProcessTrusted()
    @State private var canCapture = CGPreflightScreenCaptureAccess()
    @State private var testResult = ""
    @State private var testing = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule().fill(index <= step ? SuggestionView.brand : Color.secondary.opacity(0.25))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
                Spacer()
                Text("\(step + 1) / 3").font(.caption).foregroundStyle(.secondary)
            }
            .animation(Motion.reveal, value: step)

            Group {
                switch step {
                case 0: permissions
                case 1: keys
                default: identity
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                if step > 0 { Button(L("上一步")) { step -= 1 } }
                Spacer()
                Button(step == 2 ? L("開始使用") : L("下一步")) { step == 2 ? finish() : (step += 1) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!stepDone)
            }
        }
        .padding(28)
        .frame(width: 520, height: 500)
        .onReceive(tick) { _ in
            trusted = AXIsProcessTrusted()
            canCapture = CGPreflightScreenCaptureAccess()
        }
    }

    private var stepDone: Bool {
        switch step {
        case 0: trusted
        case 1: !settings.openRouterKey.isEmpty && Prefs.keyProblem(settings.openRouterKey, prefix: "sk-or-") == nil
        default: true
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("讓 Wingman 看得到聊天")).font(.title2.bold())
            Text(L("Wingman 讀你正在看的對話，幫你想好 3 句回覆，你選一句填進輸入框，自己按 Enter 送出。它不會自動送出任何訊息。"))
                .foregroundStyle(.secondary)
            permissionRow(done: trusted, title: L("輔助使用（必要）"),
                          detail: L("讀 Slack、Discord 的對話，並把回覆填進輸入框。"),
                          pane: "Privacy_Accessibility")
            permissionRow(done: canCapture, title: L("螢幕與系統錄音（用 LINE、Telegram 才需要）"),
                          detail: L("這兩個 App 只能看畫面讀字，截圖只在這台 Mac 上辨識，不會上傳。開啟後要重新啟動 Wingman。"),
                          pane: "Privacy_ScreenCapture", request: CGRequestScreenCaptureAccess)
        }
    }

    private func permissionRow(done: Bool, title: String, detail: String, pane: String,
                               request: (() -> Bool)? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(done ? .green : .secondary)
            SettingPurpose(title, detail)
            Spacer()
            if !done {
                Button(L("打開設定")) {
                    _ = request?()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("連上 AI")).font(.title2.bold())
            SettingPurpose(L("寫回覆：OpenRouter（必要）"),
                           L("按用量付費，先儲值（例如 US$5）就好；一次建議大約 US$0.0002。"))
            SecureField("OpenRouter API key（sk-or-v1-…）", text: trimmedKey($settings.openRouterKey))
                .textFieldStyle(.roundedBorder)
            if let problem = Prefs.keyProblem(settings.openRouterKey, prefix: "sk-or-") {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                Link(L("申請 key ↗"), destination: URL(string: "https://openrouter.ai/keys")!)
                Link(L("儲值 ↗"), destination: URL(string: "https://openrouter.ai/settings/credits")!)
            }
            .font(.callout)
            SettingPurpose(L("判斷訊息：TypeSafe（選填）"), L("填了判斷會快幾秒；沒填也能用。"))
            SecureField("TypeSafe API key", text: trimmedKey($settings.typesafeKey))
                .textFieldStyle(.roundedBorder)
            HStack {
                Link(L("申請 key ↗"), destination: URL(string: "https://console.typesafe.ai/keys")!).font(.callout)
                Spacer()
                Button(testing ? L("測試中…") : L("測試連線")) {
                    testing = true
                    Task {
                        testResult = await Brain(settings: settings, app: .slack).testConnection()
                        testing = false
                    }
                }
                .disabled(testing || settings.openRouterKey.isEmpty)
            }
            if !testResult.isEmpty { Text(testResult).font(.caption) }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("最後一步")).font(.title2.bold())
            SettingPurpose(L("你在聊天 App 裡顯示的名字"),
                           L("用來分辨 Slack、Discord 裡哪些是你說的。名字不只一個就用逗號分開，例如「Yii, Yii Chen」。"))
            TextField(L("你的名字"), text: $settings.myName).textFieldStyle(.roundedBorder)
            HotkeyRecorder(settings: settings)
            Text(L("好了之後，打開一個對方最後說話的對話，輸入框上方會出現「✦ 3 個建議」。按 %@ 展開，按 Enter 填入最推薦的那句。", "\(settings.hotkey.label)"))
                .font(.callout)
                .padding(12)
                .background(SuggestionView.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
