import Foundation

public struct Candidate: Equatable {
    public var strategy: String
    public var text: String
    /// Jev's probability that this is the draft to send; nil until ranked.
    public var score: Double?
}

public enum CandidateDecoder {
    public struct Malformed: Error {}

    /// `data` is an OpenAI-compatible chat completion; the reply texts are a JSON array inside its content.
    public static func candidates(from data: Data) throws -> [Candidate] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = ((root["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw Malformed() }

        let items = jsonSlices(of: content).lazy.compactMap(items(in:)).first ?? []
        let candidates = items.compactMap { item -> Candidate? in
            let text = (item["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Candidate(strategy: item["strategy"] as? String ?? "", text: text)
        }
        guard !candidates.isEmpty else { throw Malformed() }
        return candidates
    }

    /// Models wrap JSON in prose or code fences; try the whole text, then the outermost array or object.
    private static func jsonSlices(of content: String) -> [Substring] {
        var slices = [Substring(content)]
        for (open, close) in [("[", "]"), ("{", "}")] {
            if let start = content.firstIndex(of: Character(open)), let end = content.lastIndex(of: Character(close)),
               start < end {
                slices.append(content[start...end])
            }
        }
        return slices
    }

    private static func items(in json: Substring) -> [[String: Any]]? {
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return nil }
        if let array = value as? [[String: Any]] { return array }
        return (value as? [String: Any])?["candidates"] as? [[String: Any]]
    }
}
