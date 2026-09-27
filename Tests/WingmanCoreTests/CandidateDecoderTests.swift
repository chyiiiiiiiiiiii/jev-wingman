import Foundation
import Testing
@testable import WingmanCore

/// Wraps model output in the OpenAI chat-completion envelope OpenRouter returns.
private func completion(_ content: String) -> Data {
    let envelope: [String: Any] = ["id": "gen-1", "choices": [["index": 0, "message": ["role": "assistant", "content": content]]]]
    return try! JSONSerialization.data(withJSONObject: envelope)
}

@Test func readsAPlainJSONArray() throws {
    let content = #"[{"strategy":"給進度和時間","text":"測試快跑完了，預計五點前發版"},{"strategy":"答應但附條件","text":"可以，只要 QA 五點前簽核"},{"strategy":"直接答應","text":"可以，今天下班前發"}]"#

    #expect(try CandidateDecoder.candidates(from: completion(content)) == [
        Candidate(strategy: "給進度和時間", text: "測試快跑完了，預計五點前發版"),
        Candidate(strategy: "答應但附條件", text: "可以，只要 QA 五點前簽核"),
        Candidate(strategy: "直接答應", text: "可以，今天下班前發"),
    ])
}

@Test func toleratesProseFencesAndAWrapperObjectAndDropsEmptyTexts() throws {
    let content = """
    好的，以下是三個回覆：
    ```json
    {"candidates": [{"strategy": "先問清楚", "text": "是哪一個客戶在問？"}, {"strategy": "簡短回應", "text": "  "}]}
    ```
    """

    #expect(try CandidateDecoder.candidates(from: completion(content)) == [
        Candidate(strategy: "先問清楚", text: "是哪一個客戶在問？"),
    ])
}

@Test func rejectsARefusal() {
    #expect(throws: CandidateDecoder.Malformed.self) {
        try CandidateDecoder.candidates(from: completion("抱歉，我無法協助這個請求。"))
    }
}
