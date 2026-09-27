/// The judgments asked of Jev about the message to answer. Option order matters: it breaks ties
/// between equally likely strategies (see `JevDecoder`).
public enum ReplyQuestions {
    public static let intents: [(String, String)] = [
        ("問資訊", "想知道一個事實、狀態或答案"),
        ("請求或交辦", "要 `me` 做某件事或幫忙"),
        ("催進度或要時間", "要 `me` 給出完成時間或進度"),
        ("確認或同意", "要 `me` 同意、確認或拍板"),
        ("告知", "只是通知或回報，不需要 `me` 做決定"),
        ("閒聊", "打招呼、寒暄或隨口聊"),
        ("抱怨或不滿", "表達不滿、責怪或情緒"),
        ("感謝或稱讚", "道謝或肯定"),
    ]

    public static let strategies: [(String, String)] = [
        ("直接答應", "同意並給出明確承諾"),
        ("答應但附條件", "可以，但說明前提、風險或需要的東西"),
        ("給進度和時間", "說明目前狀態並給出預估時間"),
        ("先問清楚", "資訊不足，先反問釐清"),
        ("婉拒或延後", "做不到或現在不行，有禮貌地拒絕或改期"),
        ("表達感謝", "道謝或肯定對方"),
        ("簡短回應", "一兩個字表示收到或認同即可"),
    ]

    public static let urgencyLevels = [
        "不回也沒關係，或幾天內再回即可",
        "今天內回就好",
        "最好一小時內回",
        "對方正在等，應該馬上回",
    ]

    public static var strategyOrder: [String] { strategies.map(\.0) }

    public static func description(ofStrategy name: String) -> String {
        strategies.first { $0.0 == name }?.1 ?? name
    }

    /// The `questions` map of a System One request; state carries `me` and `reply_to`.
    public static var payload: [String: Any] {
        [
            "intent": ["type": "choice",
                       "instructions": "`reply_to` 是對方傳給 `me` 的訊息。對方主要想從 `me` 這裡得到什麼？",
                       "criteria": Dictionary(uniqueKeysWithValues: intents)],
            "needs_reply": ["type": "noul", "instructions": "`me` 需要回覆 `reply_to` 嗎？"],
            "urgency": ["type": "score", "instructions": "`me` 應該多快回覆 `reply_to`？", "criteria": urgencyLevels],
            "strategy": ["type": "choice",
                         "instructions": "`me` 回覆 `reply_to` 時，哪一種回法最能推進這段對話？",
                         "criteria": Dictionary(uniqueKeysWithValues: strategies)],
        ]
    }
}
