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

// Recorded from api.typesafe.ai on 2026-09-27: which of three drafts best answers "感恩 :)".
private let recordedRanking = #"""
{"model":"jev-1.13.0","answers":{"best":{"type":"choice","choice":"不客氣，有需要再跟我說！","confidence":0.98,"probabilities":{"不客氣，有需要再跟我說！":0.99,"沒問題，我回去就開始處理，整理好會馬上跟你回報。":0.0,"想先確認一下，這兩份附件是要我一起彙整進大家的資訊裡，還是先參考就好？":0.01}}},"usage":{"input_tokens":525,"output_tokens":119}}
"""#

@Test func scoresEachDraftInTheOrderItWasShown() throws {
    let drafts = ["沒問題，我回去就開始處理，整理好會馬上跟你回報。", "不客氣，有需要再跟我說！",
                  "想先確認一下，這兩份附件是要我一起彙整進大家的資訊裡，還是先參考就好？", "Jev 沒看過的草稿"]

    let scores = try JevDecoder.scores(from: Data(recordedRanking.utf8), for: drafts)

    #expect(scores == [0.0, 0.99, 0.01, 0.0])
}

@Test func aPostJudgmentHasNoReplyOrUrgencyQuestion() throws {
    // Posts ask only what the author is doing and which way to reply; a reply is wanted by definition.
    let post = #"{"answers":{"intent":{"type":"choice","choice":"提問或求助","confidence":0.8,"probabilities":{"提問或求助":0.9}},"strategy":{"type":"choice","choice":"分享經驗","probabilities":{"分享經驗":0.7,"提出問題":0.3}}}}"#
    let j = try JevDecoder.judgment(from: Data(post.utf8), strategyOrder: ReplyQuestions.postStrategyOrder)
    #expect(j.intent == "提問或求助")
    #expect(j.needsReply == 1)
    #expect(j.urgency == nil)
    #expect(j.strategies.prefix(2).map(\.name) == ["分享經驗", "提出問題"])
}
