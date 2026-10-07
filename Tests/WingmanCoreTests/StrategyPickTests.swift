import Testing
@testable import WingmanCore

private func ranked(_ names: [String]) -> [Strategy] {
    names.enumerated().map { Strategy(name: $1, probability: 1 - Double($0) * 0.1) }
}

@Test func threeWaysOfSayingYesMakeRoomForANo() {
    // Jev's order for "API 文件今天來得及更新嗎？" (jev-1.13.0, recorded 2026-09-27): three kinds of yes.
    let strategies = ranked(["給進度和時間", "答應但附條件", "直接答應", "先問清楚", "婉拒或延後", "表達感謝", "簡短回應"])
    #expect(ReplyQuestions.picks(from: strategies) == ["給進度和時間", "答應但附條件", "婉拒或延後"])
}

@Test func picksThatAlreadyLeaveAWayOutStayAsJevRankedThem() {
    let strategies = ranked(["直接答應", "先問清楚", "給進度和時間", "婉拒或延後", "答應但附條件", "表達感謝", "簡短回應"])
    #expect(ReplyQuestions.picks(from: strategies) == ["直接答應", "先問清楚", "給進度和時間"])
    let thanks = ranked(["表達感謝", "簡短回應", "直接答應", "先問清楚", "婉拒或延後", "答應但附條件", "給進度和時間"])
    #expect(ReplyQuestions.picks(from: thanks) == ["表達感謝", "簡短回應", "直接答應"])
}

@Test func repliesUnderAPostAreLeftAlone() {
    let strategies = ranked(["共鳴附和", "補充觀點", "讚美鼓勵", "提出問題", "分享經驗", "幽默回應", "禮貌提出不同看法"])
    #expect(ReplyQuestions.picks(from: strategies) == ["共鳴附和", "補充觀點", "讚美鼓勵"])
}

@Test func aTenseChatIsNoPlaceToOfferANo() {
    // "算了，你忙你的吧，我自己弄" (jev-1.13.0, 2026-10-07): the drafts should settle things, not decline.
    let strategies = ranked(["給進度和時間", "直接答應", "答應但附條件", "先問清楚", "婉拒或延後", "表達感謝", "簡短回應"])
    #expect(ReplyQuestions.picks(from: strategies, tense: true) == ["給進度和時間", "直接答應", "答應但附條件"])
}
