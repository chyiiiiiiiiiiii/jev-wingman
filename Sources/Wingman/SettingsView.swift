import AppKit
import ApplicationServices
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Prefs
    @ObservedObject var model: AppModel
    @State private var trusted = AXIsProcessTrusted()
    @State private var testResult = ""
    @State private var testing = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                SecureField("OpenRouter API key（寫回覆用，sk-or-…）", text: $settings.openRouterKey)
                SecureField("TypeSafe API key（Jev 判斷用，選填）", text: $settings.typesafeKey)
                Text("Jev 只做判斷、不會寫字，所以寫回覆需要 OpenRouter。有 TypeSafe key 時 Jev 直連 TypeSafe，沒有就透過 OpenRouter 呼叫。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("去 OpenRouter 申請 key ↗", destination: URL(string: "https://openrouter.ai/keys")!)
                    Spacer()
                    Button(testing ? "測試中…" : "測試連線") {
                        testing = true
                        Task {
                            testResult = await Brain(settings: settings).testConnection()
                            testing = false
                        }
                    }
                    .disabled(testing)
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).textSelection(.enabled)
                }
                DisclosureGroup("進階") {
                    TextField("寫回覆的模型", text: $settings.model)
                    Text("聊天內容會直接從這台 Mac 送到 OpenRouter／TypeSafe，不經過其他伺服器。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("2. 連上 AI") }

            Section {
                TextField("你在 Slack 顯示的名字", text: $settings.myName)
                let senders = Array(Set(model.conversation?.messages.compactMap(\.sender) ?? [])).sorted()
                if !senders.isEmpty {
                    HStack {
                        Text("是其中一個嗎？").font(.caption).foregroundStyle(.secondary)
                        ForEach(senders, id: \.self) { name in
                            Button(name) { settings.myName = name }.controlSize(.small)
                        }
                    }
                }
                Text("用來分辨哪些訊息是你自己說的。").font(.caption).foregroundStyle(.secondary)
            } header: { Text("3. 你是誰") }

            Section {
                Text("Slack 收到訊息時，輸入框右上方會出現「✦ 3 個建議」。按 \(model.hotkeyLabel) 或點它展開，按 1、2、3 填進輸入框，確認後自己按 Enter 送出。")
                    .font(.callout)
            } header: { Text("怎麼用") }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onReceive(tick) { _ in trusted = AXIsProcessTrusted() }
    }
}
