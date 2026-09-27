import Testing
@testable import WingmanCore

private let chineseThread = ["Google 釋出了新的 TTS 模型", "我拿來做了一個學日文歌的網站"]

@Test func chineseWithEnglishTermsIsChinese() {
    // NLLanguageRecognizer said "en" and "ro" for these on 2026-09-27.
    #expect(ReplyLanguage.pick(replyTo: "API 應該用streaming 嗎?", recent: chineseThread) == .chinese)
    #expect(ReplyLanguage.pick(replyTo: "PR 可以 merge 了嗎", recent: []) == .chinese)
}

@Test func kanaMeansJapaneseAndHangulKorean() {
    #expect(ReplyLanguage.pick(replyTo: "ありがとう、助かりました", recent: chineseThread) == .japanese)
    #expect(ReplyLanguage.pick(replyTo: "감사합니다", recent: []) == .korean)
}

@Test func aShortLatinMessageFollowsTheThreadAndALongOneIsAnsweredInKind() {
    #expect(ReplyLanguage.pick(replyTo: "LGTM 👍", recent: chineseThread) == .chinese)
    #expect(ReplyLanguage.pick(replyTo: "Sounds good, let's ship it tomorrow morning then", recent: chineseThread) == .theirs)
    #expect(ReplyLanguage.pick(replyTo: "LGTM 👍", recent: ["Merged the fix", "Deploying now"]) == .theirs)
}
