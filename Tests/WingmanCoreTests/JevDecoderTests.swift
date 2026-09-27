import Foundation
import Testing
@testable import WingmanCore

// Recorded from api.typesafe.ai on 2026-09-27 (jev-1.13.0) for a synthetic Slack thread.
private let recorded = #"""
{"model":"jev-1.13.0","answers":{
 "intent":{"type":"choice","choice":"催進度或要時間","confidence":0.93,"probabilities":{"請求或交辦":0.0,"確認或同意":0.01,"告知":0.0,"催進度或要時間":0.94,"問資訊":0.05,"閒聊":0.0,"感謝或稱讚":0.0,"抱怨或不滿":0.0}},
 "needs_reply":{"type":"noul","noul":0.91},
 "urgency":{"type":"score","score":2.94,"confidence":0.94,"legend":{"0":"a","1":"b","2":"c","3":"d"},"probabilities":{"0":0.0,"1":0.0,"2":0.05,"3":0.95}},
 "strategy":{"type":"choice","choice":"給進度和時間","confidence":0.92,"probabilities":{"簡短回應":0.0,"婉拒或延後":0.0,"直接答應":0.0,"給進度和時間":0.94,"表達感謝":0.0,"答應但附條件":0.06,"先問清楚":0.0}}},
 "usage":{"input_tokens":1057,"output_tokens":234}}
"""#

private let offered = ["直接答應", "答應但附條件", "給進度和時間", "先問清楚", "婉拒或延後", "表達感謝", "簡短回應"]

@Test func decodesTheRecordedJudgment() throws {
    let j = try JevDecoder.judgment(from: Data(recorded.utf8), strategyOrder: offered)

    #expect(j.intent == "催進度或要時間")
    #expect(j.intentConfidence == 0.93)
    #expect(j.needsReply == 0.91)
    #expect(j.urgency == 2.94)
    // 0.94 and 0.06, then the zero-probability options in the order they were offered.
    #expect(j.strategies.prefix(3).map(\.name) == ["給進度和時間", "答應但附條件", "直接答應"])
    #expect(j.strategies.count == 7)
}

@Test func rejectsAResponseWithoutAnswers() {
    #expect(throws: JevDecoder.Malformed.self) {
        try JevDecoder.judgment(from: Data(#"{"error":"rate limited"}"#.utf8), strategyOrder: offered)
    }
}
