import Foundation
import WingmanCore

/// Jev picks how to answer; an LLM writes one reply per pick.
struct Brain {
    enum Failure: LocalizedError {
        case missingKey, http(Int, String), nothingToAnswer

        var errorDescription: String? {
            switch self {
            case .missingKey: "還沒設定 OpenRouter API key"
            case let .http(code, body): "服務回應 \(code)：\(body.prefix(120))"
            case .nothingToAnswer: "畫面上沒有可以回覆的訊息"
            }
        }
    }

    let settings: Prefs
    static let contextLimit = 20

    func judge(_ convo: Conversation) async throws -> Judgment {
        guard let replyTo = convo.messages.last(where: { !$0.isMe }) else { throw Failure.nothingToAnswer }
        let body: [String: Any] = ["model": jevModel, "state": state(convo, replyTo: replyTo),
                                   "questions": ReplyQuestions.payload]
        let data = try await post(jevURL, key: jevKey, body: body)
        return try JevDecoder.judgment(from: data, strategyOrder: ReplyQuestions.strategyOrder)
    }

    /// One reply per strategy, in the given order.
    func write(_ convo: Conversation, strategies: [String], judgment: Judgment?) async throws -> [Candidate] {
        let asks = strategies.map { "- \($0)：\(ReplyQuestions.description(ofStrategy: $0))" }.joined(separator: "\n")
        var brief = strategies.isEmpty
            ? "請寫三則回法不同的回覆，strategy 欄位用兩到六個字描述那一則的回法。"
            : "請依照下面每一種回法各寫一則回覆，順序不變：\n\(asks)"
        if let judgment {
            brief = "對方的意圖：\(judgment.intent)。\n" + brief
        }
        return try await complete(convo, brief: brief)
    }

    /// Rewrites along the user's own direction ("更短", or "跟他說週五前給").
    func rewrite(_ convo: Conversation, direction: String, previous: [Candidate]) async throws -> [Candidate] {
        let drafts = previous.map { "- \($0.text)" }.joined(separator: "\n")
        let brief = """
        我想這樣回：「\(direction)」
        之前的草稿（可參考，不必沿用）：
        \(drafts)
        請照我的意思寫三則不同說法的回覆，strategy 欄位用兩到六個字描述那一則的差別。
        """
        return try await complete(convo, brief: brief)
    }

    /// One line per service, for the settings window.
    func testConnection() async -> String {
        var lines: [String] = []
        if settings.openRouterKey.isEmpty {
            lines.append("✗ 還沒填 OpenRouter key")
        } else {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!, timeoutInterval: 15)
            request.setValue("Bearer \(settings.openRouterKey)", forHTTPHeaderField: "Authorization")
            let code = ((try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse)?.statusCode ?? 0
            lines.append(code == 200 ? "✓ OpenRouter key 可以用" : "✗ OpenRouter 回應 \(code)，請檢查 key")
        }
        let started = Date()
        do {
            let body: [String: Any] = ["model": jevModel, "state": "今天可以開會嗎？",
                                       "questions": ["q": ["type": "noul", "instructions": "這是一個問題嗎？"]]]
            _ = try await post(jevURL, key: jevKey, body: body)
            lines.append("✓ Jev 判斷可以用（\(Int(Date().timeIntervalSince(started) * 1000)) ms）")
        } catch {
            lines.append("✗ Jev：\(error.localizedDescription)")
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
            "app": "Slack",
            "channel": convo.title,
            "in_thread": convo.isThread,
            "me": settings.myName.isEmpty ? "我" : settings.myName,
            "conversation": convo.messages.suffix(Self.contextLimit).map { message -> [String: Any] in
                ["sender": message.isMe ? (settings.myName.isEmpty ? "我" : settings.myName) : (message.sender ?? "（不明）"),
                 "text": message.text]
            },
            "reply_to": replyTo.text,
        ]
    }

    private func complete(_ convo: Conversation, brief: String) async throws -> [Candidate] {
        guard !settings.openRouterKey.isEmpty else { throw Failure.missingKey }
        let me = settings.myName.isEmpty ? "我" : settings.myName
        let transcript = convo.messages.suffix(Self.contextLimit).map { m in
            "\(m.isMe ? "\(me)（我）" : (m.sender ?? "（不明）"))：\(m.text)"
        }.joined(separator: "\n")
        let user = """
        Slack \(convo.isThread ? "對話串" : "頻道") \(convo.title)
        我的名字：\(me)
        最近的對話（由舊到新）：
        \(transcript)

        \(brief)
        """
        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0.7,
            "max_tokens": 700,
            "messages": [["role": "system", "content": Self.writerRules], ["role": "user", "content": user]],
        ]
        let data = try await post(URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                                  key: settings.openRouterKey, body: body)
        return try CandidateDecoder.candidates(from: data)
    }

    static let writerRules = """
    你替使用者（「我」）起草要在 Slack 回給同事的訊息。
    - 每則回覆就是我會直接送出的原文：不加引號、不加說明、不署名。
    - 用對方使用的語言回覆；中文一律用臺灣繁體中文與臺灣用語。
    - 語氣像真人同事：自然、簡潔、有禮，不要客服腔，不要過度客套或堆砌表情符號。
    - 一則只寫一段，不換行，通常一到兩句。
    - 不要編造對話裡沒有的事實、數字、日期或承諾；需要但不知道時，留下像 [時間] 這樣的空格讓我自己填。
    - 只輸出 JSON 陣列，不要其他文字：[{"strategy": "<回法>", "text": "<回覆>"}]
    """

    private func post(_ url: URL, key: String, body: [String: Any]) async throws -> Data {
        guard !key.isEmpty else { throw Failure.missingKey }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Wingman", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }
}
