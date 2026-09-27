import Foundation
import WingmanCore

/// Jev picks how to answer; an LLM writes one reply per pick.
struct Brain {
    enum Failure: LocalizedError {
        case missingKey, http(Int, String), nothingToAnswer

        var errorDescription: String? {
            switch self {
            case .missingKey: L("還沒設定 OpenRouter API key")
            case let .http(code, body): Self.explain(code, body)
            case .nothingToAnswer: L("畫面上沒有可以回覆的訊息")
            }
        }

        /// What went wrong in words, from the status alone. The body is read only to recognise a
        /// model without zero-retention providers; it is never shown or logged, since it can quote
        /// the request, which is someone's conversation.
        static func explain(_ code: Int, _ body: String) -> String {
            switch code {
            case 401, 403: L("key 無效或沒有權限（%@）", "\(code)")
            case 402: L("OpenRouter 餘額不足，請儲值（%@）", "\(code)")
            case 404 where body.lowercased().contains("endpoint"): L("這個模型沒有「不保留資料」的供應商，請換一個模型（%@）", "\(code)")
            case 429: L("請求太頻繁，稍等一下再試（%@）", "\(code)")
            case 500...: L("服務暫時有問題，稍後再試（%@）", "\(code)")
            default: L("服務回應 %@", "\(code)")
            }
        }
    }

    let settings: Prefs
    let app: ChatApp
    static let contextLimit = 20

    func judge(_ convo: Conversation) async throws -> Judgment {
        guard let replyTo = convo.messages.last(where: { !$0.isMe }) else { throw Failure.nothingToAnswer }
        let body: [String: Any] = ["model": jevModel, "state": state(convo, replyTo: replyTo),
                                   "questions": ReplyQuestions.payload]
        let data = try await post(jevURL, key: jevKey, body: body)
        let usage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["usage"] as? [String: Any]
        let tokens = usage?["input_tokens"] as? Int ?? 0
        Log.write("jev tokens in=\(tokens) cost=$\(String(format: "%.6f", Double(tokens) * 0.042 / 1_000_000))")
        return try JevDecoder.judgment(from: data, strategyOrder: ReplyQuestions.strategyOrder)
    }

    /// Jev's pick among the drafts, as a probability per draft in the order given.
    func rank(_ convo: Conversation, drafts: [String]) async throws -> [Double] {
        guard let replyTo = convo.messages.last(where: { !$0.isMe }) else { throw Failure.nothingToAnswer }
        let criteria = Dictionary(drafts.map { ($0, NSNull()) }, uniquingKeysWith: { first, _ in first })
        let body: [String: Any] = ["model": jevModel, "state": state(convo, replyTo: replyTo),
                                   "questions": ["best": ["type": "choice", "instructions": ReplyQuestions.rankInstructions,
                                                          "criteria": criteria]]]
        let data = try await post(jevURL, key: jevKey, body: body)
        return try JevDecoder.scores(from: data, for: drafts)
    }

    /// Called with the drafts finished so far while the model is still writing.
    typealias Drafts = @Sendable ([Candidate]) async -> Void

    /// One reply per strategy, in the given order.
    func write(_ convo: Conversation, strategies: [String], judgment: Judgment?,
               onDrafts: @escaping Drafts) async throws -> [Candidate] {
        let asks = strategies.map { "- \($0)：\(ReplyQuestions.description(ofStrategy: $0))" }.joined(separator: "\n")
        var brief = strategies.isEmpty
            ? "請寫三則回法不同的回覆，strategy 欄位用兩到六個字描述那一則的回法\(Self.labelLanguage)。"
            : "請依照下面每一種回法各寫一則回覆，順序不變：\n\(asks)"
        if let judgment {
            brief = "對方的意圖：\(judgment.intent)。\n" + brief
        }
        return try await complete(convo, brief: brief, onDrafts: onDrafts)
    }

    /// Rewrites along the user's own direction ("更短", or "跟他說週五前給").
    func rewrite(_ convo: Conversation, direction: String, previous: [Candidate],
                 onDrafts: @escaping Drafts) async throws -> [Candidate] {
        let drafts = previous.map { "- \($0.text)" }.joined(separator: "\n")
        let brief = """
        我想這樣回：「\(direction)」
        之前的草稿（可參考，不必沿用）：
        \(drafts)
        請照我的意思寫三則不同說法的回覆，strategy 欄位用兩到六個字描述那一則的差別\(Self.labelLanguage)。
        """
        return try await complete(convo, brief: brief, onDrafts: onDrafts)
    }

    /// One line per service, for the settings window.
    func testConnection() async -> String {
        var lines: [String] = []
        if settings.openRouterKey.isEmpty {
            lines.append(L("✗ 還沒填 OpenRouter key"))
        } else {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!, timeoutInterval: 15)
            request.setValue("Bearer \(settings.openRouterKey)", forHTTPHeaderField: "Authorization")
            let code = ((try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse)?.statusCode ?? 0
            lines.append(code == 200 ? L("✓ OpenRouter key 可以用") : L("✗ OpenRouter 回應 %@，請檢查 key", "\(code)"))
        }
        let started = Date()
        do {
            let body: [String: Any] = ["model": jevModel, "state": "今天可以開會嗎？",
                                       "questions": ["q": ["type": "noul", "instructions": "這是一個問題嗎？"]]]
            _ = try await post(jevURL, key: jevKey, body: body)
            lines.append(L("✓ 判斷訊息可以用（TypeSafe Jev，%@ ms）", "\(Int(Date().timeIntervalSince(started) * 1000))"))
        } catch {
            lines.append(L("✗ 判斷訊息（TypeSafe Jev）：%@", "\(error.localizedDescription)"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Requests

    private var jevURL: URL {
        settings.typesafeKey.isEmpty ? URL(string: "https://openrouter.ai/api/alpha/decisions")!
            : URL(string: "https://api.typesafe.ai/v1/systemone")!
    }
    private var jevKey: String { settings.typesafeKey.isEmpty ? settings.openRouterKey : settings.typesafeKey }
    private var jevModel: String { settings.typesafeKey.isEmpty ? "typesafe/jev-1.13" : "jev-latest" }

    private func state(_ convo: Conversation, replyTo: ChatMessage) -> [String: Any] {
        [
            "app": app.name,
            "channel": convo.title,
            "in_thread": convo.isThread,
            "me": settings.myName.isEmpty ? "我" : settings.myName,
            "conversation": convo.messages.suffix(Self.contextLimit).map { message -> [String: Any] in
                ["sender": message.isMe ? (settings.myName.isEmpty ? "我" : settings.myName) : (message.sender ?? "（不明）"),
                 "text": message.text]
            },
            "reply_to": replyTo.text,
        ].merging(convo.hasAttachments ? ["attachments": Self.attachmentNote] : [:]) { $1 }
    }

    /// What 📎 stands for, told to Jev and the writer only when the conversation has one.
    static let attachmentNote = "「📎」是一張照片、一段影片、一個貼圖或一則分享的貼文，看不到內容，不要猜裡面是什麼。"

    private func complete(_ convo: Conversation, brief: String, onDrafts: Drafts) async throws -> [Candidate] {
        guard !settings.openRouterKey.isEmpty else { throw Failure.missingKey }
        let me = settings.myName.isEmpty ? "我" : settings.myName
        let transcript = convo.messages.suffix(Self.contextLimit).map { m in
            "\(m.isMe ? "\(me)（我）" : (m.sender ?? "（不明）"))：\(m.text)"
        }.joined(separator: "\n")
        let user = """
        \(app.name)\(convo.isThread ? " 對話串" : "") \(convo.title)
        \(Self.languageRule(for: convo))
        我的名字：\(me)
        最近的對話（由舊到新）：
        \(transcript)
        \(convo.hasAttachments ? Self.attachmentNote : "")

        \(brief)
        """
        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0.7,
            "max_tokens": 700,
            "stream": true,     // drafts show up one by one instead of all after 2–4 s
            "usage": ["include": true],   // OpenRouter then reports the charge in the response
            "reasoning": ["enabled": false],   // thinking adds seconds and output tokens to a two-line reply
            // Slack threads are company data: keep them off hosts in mainland China, and try hosts
            // that were quick from Taiwan first (bench 2026-09-27: 2–4 s, cheapest host 9–17 s).
            // Only providers that neither keep nor train on the text (zero data retention), and none in
            // mainland China. Checked 2026-09-27: all three picker models still route (Fireworks, Google,
            // Amazon Bedrock).
            "provider": ["order": Self.preferredProviders, "ignore": Self.excludedProviders,
                         "data_collection": "deny", "zdr": true],
            "messages": [["role": "system", "content": Self.writerRules(for: app)], ["role": "user", "content": user]],
        ]
        var request = try jsonRequest(URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                                      key: settings.openRouterKey, body: body)
        request.timeoutInterval = 45
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var reply = Data()
            for try await byte in bytes where reply.count < 2000 { reply.append(byte) }
            throw Failure.http(code, String(decoding: reply, as: UTF8.self))
        }
        // Server-sent events: "data: {chunk}" lines, then "data: [DONE]"; the last chunk carries usage.
        var content = "", shown = 0
        var usage: [String: Any]?
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            let payload = line.dropFirst(6)
            if payload == "[DONE]" { break }
            guard let chunk = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            if let reported = chunk["usage"] as? [String: Any] { usage = reported }
            let delta = ((chunk["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String
            guard let delta else { continue }
            content += delta
            let drafts = CandidateDecoder.completed(inPartial: content)
            if drafts.count > shown {
                shown = drafts.count
                await onDrafts(drafts)
            }
        }
        Log.write("write model=\(settings.model) tokens in=\(usage?["prompt_tokens"] as? Int ?? 0) "
                  + "out=\(usage?["completion_tokens"] as? Int ?? 0) cost=$\(usage?["cost"] as? Double ?? 0)")
        return try CandidateDecoder.candidates(fromContent: content)
    }

    /// Say which language answers; left to themselves, models drift with whatever the thread is in.
    static func languageRule(for convo: Conversation) -> String {
        let replyTo = convo.messages.last(where: { !$0.isMe })?.text ?? ""
        let recent = convo.messages.suffix(8).map(\.text)
        switch ReplyLanguage.pick(replyTo: replyTo, recent: recent) {
        case .chinese: return "請用臺灣繁體中文回覆，技術名詞照對方的寫法保留英文。"
        case .japanese: return "對方用日文，請用日文回覆。"
        case .korean: return "對方用韓文，請用韓文回覆。"
        case .theirs: return "對方這則不是中文，請用對方訊息的語言回覆。"
        }
    }

    /// Strategy labels the model makes up are shown as they come, so ask for the interface's language.
    static var labelLanguage: String {
        let names = ["en": "英文", "zh-Hans": "簡體中文", "ja": "日文", "ko": "韓文", "es": "西班牙文", "fr": "法文", "de": "德文"]
        return names[interfaceLanguage].map { "，用\($0)寫" } ?? ""
    }

    static let excludedProviders = ["DeepSeek", "StreamLake", "Alibaba", "SiliconFlow", "Baidu"]
    static let preferredProviders = ["Fireworks", "Together", "BaseTen", "DeepInfra"]

    static func writerRules(for app: ChatApp) -> String { """
    你替使用者（「我」）起草要在 \(app.name) 回覆的訊息。
    - 每則回覆就是我會直接送出的原文：不加引號、不加說明、不署名。
    - 用對方使用的語言回覆；中文一律用臺灣繁體中文與臺灣用語。
    - \(app.register)
    - 一則只寫一段，不換行，通常一到兩句。
    - 不要編造對話裡沒有的事實、數字、日期或承諾；需要但不知道時，留下像 [時間] 這樣的空格讓我自己填。
    - 只輸出 JSON 陣列，不要其他文字：[{"strategy": "<回法>", "text": "<回覆>"}]
    """ }

    private func jsonRequest(_ url: URL, key: String, body: [String: Any]) throws -> URLRequest {
        guard !key.isEmpty else { throw Failure.missingKey }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Wingman", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func post(_ url: URL, key: String, body: [String: Any]) async throws -> Data {
        let request = try jsonRequest(url, key: key, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }
}
