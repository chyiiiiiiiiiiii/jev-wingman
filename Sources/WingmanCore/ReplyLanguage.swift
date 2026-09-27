/// Which language a reply should be in. Taiwanese tech chat mixes English terms into Chinese
/// ("PR 可以 merge 了嗎"), which statistical detectors call English or even Romanian, so the
/// decision rests on the scripts in the text instead.
public enum ReplyLanguage: Equatable {
    case chinese, japanese, korean, theirs

    public static func pick(replyTo: String, recent: [String]) -> ReplyLanguage {
        if replyTo.unicodeScalars.contains(where: isKana) { return .japanese }
        if replyTo.unicodeScalars.contains(where: isHangul) { return .korean }
        if replyTo.unicodeScalars.contains(where: isHan) { return .chinese }
        // "LGTM", "OK 👍": too short to say anything; answer in the thread's language.
        let letters = replyTo.unicodeScalars.filter { $0.properties.isAlphabetic }.count
        let chineseThread = recent.filter { $0.unicodeScalars.contains(where: isHan) }.count * 2 > recent.count
        return letters <= 12 && chineseThread ? .chinese : .theirs
    }

    private static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }

    private static func isKana(_ s: Unicode.Scalar) -> Bool { (0x3040...0x30FF).contains(s.value) }

    private static func isHangul(_ s: Unicode.Scalar) -> Bool { (0xAC00...0xD7AF).contains(s.value) }
}
