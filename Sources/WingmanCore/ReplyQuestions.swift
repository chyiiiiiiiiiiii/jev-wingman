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

    /// How close a chat is to a fight, after jev-chat-jarvis's `danger_level` (its ten levels folded into five).
    public static let tensionLevels = [
        "平和：閒聊或玩笑，沒有抱怨、沒有試探",
        "留意：小小的提醒或輕微不滿，好好回就沒事",
        "緊張：明顯不高興、諷刺或冷淡的短回，回得隨便會升溫",
        "快吵架：公開指責或生氣，回錯一句就會吵起來",
        "翻臉：撂下狠話或最後通牒，或已經說不想再談",
    ]

    /// What someone posting publicly (a post on Threads or Instagram, or a comment under one) is doing.
    public static let postIntents: [(String, String)] = [
        ("分享觀點", "發表看法、評論或心得"),
        ("分享生活或成果", "分享近況、作品、成就或好消息"),
        ("提問或求助", "想得到答案、建議或推薦"),
        ("徵求互動", "邀大家留言、投票或分享經驗"),
        ("宣傳或公告", "推廣產品、活動或發布消息"),
        ("心情抒發", "抒發情緒、感嘆或吐苦水"),
        ("幽默或玩梗", "搞笑、玩梗或輕鬆內容"),
    ]

    /// Ways to answer in public, where many others read along.
    public static let postStrategies: [(String, String)] = [
        ("共鳴附和", "表示認同或有同感"),
        ("補充觀點", "補上相關的資訊、角度或例子"),
        ("提出問題", "針對內容問一個好問題，延續討論"),
        ("分享經驗", "用自己的經驗回應"),
        ("讚美鼓勵", "具體地稱讚或給予鼓勵"),
        ("幽默回應", "輕鬆、機智地回一句"),
        ("禮貌提出不同看法", "有禮貌地表達不同意見，說明理由"),
    ]

    public static var postStrategyOrder: [String] { postStrategies.map(\.0) }

    public static let postRankInstructions = "`me` 要在公開貼文底下留言回覆 `reply_to`。下面哪一則留言最適合直接發出？"
        + "考慮它是否切題、語氣是否自然得體，以及有沒有編造貼文裡沒有的事實。"

    public static let rankInstructions = "`me` 要回覆 `reply_to`。下面哪一則草稿最適合直接送出？"
        + "考慮它有沒有回應對方真正的意思、語氣是否得體，以及有沒有做出對話裡沒有根據的承諾。"

    public static func description(ofStrategy name: String) -> String {
        (strategies + postStrategies).first { $0.0 == name }?.1 ?? name
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
            "tension": ["type": "score",
                        "instructions": "這段對話現在離吵架或傷感情有多近？看現在的氣氛：對方已經真心接受道歉、"
                            + "氣氛緩和了，就照緩和後的現在評分；撂下的狠話還沒收回，就維持在高的那一級。",
                        "criteria": tensionLevels],
            "subtext": ["type": "noul",
                        "instructions": "`reply_to` 有沒有話中有話？例如在試探 `me` 記不記得、在不在乎，反諷，"
                            + "拐彎抱怨，或有沒說出口的要求。看整段對話判斷，不要只看這一句。"],
        ]
    }

    /// The questions about a public post: whether to reply and how soon do not apply.
    public static var postPayload: [String: Any] {
        [
            "intent": ["type": "choice",
                       "instructions": "`reply_to` 是一則公開貼文，或貼文底下的一則留言。發文的人主要想做什麼？",
                       "criteria": Dictionary(uniqueKeysWithValues: postIntents)],
            "strategy": ["type": "choice",
                         "instructions": "`me` 要公開留言回覆 `reply_to`，哪一種回法最自然、最能帶起好的互動？",
                         "criteria": Dictionary(uniqueKeysWithValues: postStrategies)],
        ]
    }
}

extension ReplyQuestions {
    /// The three ways to reply that get a draft each: Jev's three likeliest, except that three kinds of yes make room
    /// for a no. Smart Reply found people use suggestions more when one of them declines
    /// (arxiv.org/abs/1606.04870), and with three yeses someone who cannot do it has nothing to pick. Not in a tense
    /// chat, where the drafts should settle things first.
    public static func picks(from strategies: [Strategy], tense: Bool = false) -> [String] {
        let top = Array(strategies.prefix(3).map(\.name))
        guard !tense, top.count == 3, top.allSatisfy(yeses.contains) else { return top }
        return top.prefix(2) + ["婉拒或延後"]
    }

    static let yeses: Set = ["直接答應", "答應但附條件", "給進度和時間"]
}
