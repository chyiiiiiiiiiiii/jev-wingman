import Foundation

public struct Strategy: Equatable {
    public var name: String
    public var probability: Double
}

public struct Judgment: Equatable {
    public var intent: String
    public var intentConfidence: Double
    /// Probability that a reply is expected at all.
    public var needsReply: Double
    /// 0 = can wait days … 3 = they are waiting right now.
    public var urgency: Double
    /// Every reply strategy, most probable first.
    public var strategies: [Strategy]
}

public enum JevDecoder {
    public struct Malformed: Error {}

    /// `strategyOrder` breaks ties between equally likely strategies in the order they were offered.
    public static func judgment(from data: Data, strategyOrder: [String]) throws -> Judgment {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let intent = answers["intent"] as? [String: Any], let intentChoice = intent["choice"] as? String,
              let needsReply = (answers["needs_reply"] as? [String: Any])?["noul"] as? Double,
              let urgency = (answers["urgency"] as? [String: Any])?["score"] as? Double,
              let strategyProbs = (answers["strategy"] as? [String: Any])?["probabilities"] as? [String: Double]
        else { throw Malformed() }

        let rank = Dictionary(uniqueKeysWithValues: strategyOrder.enumerated().map { ($1, $0) })
        let strategies = strategyProbs
            .map { Strategy(name: $0.key, probability: $0.value) }
            .sorted { ($0.probability, -(rank[$0.name] ?? .max)) > ($1.probability, -(rank[$1.name] ?? .max)) }
        return Judgment(intent: intentChoice, intentConfidence: intent["confidence"] as? Double ?? 0,
                        needsReply: needsReply, urgency: urgency, strategies: strategies)
    }
}

extension JevDecoder {
    /// Probability Jev gives each draft of being the one to send, aligned with `drafts`.
    public static func scores(from data: Data, for drafts: [String]) throws -> [Double] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let best = (root["answers"] as? [String: Any])?["best"] as? [String: Any],
              let probabilities = best["probabilities"] as? [String: Double]
        else { throw Malformed() }
        return drafts.map { probabilities[$0] ?? 0 }
    }
}
