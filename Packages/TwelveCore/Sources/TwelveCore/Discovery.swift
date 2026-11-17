import Foundation

/// One editorial discovery ("Today's Spark"). Every card carries a source.
public struct DiscoveryCard: Codable, Identifiable, Equatable, Sendable {
    public struct Quiz: Codable, Equatable, Sendable {
        public let question: String
        public let options: [String]
        public let answer: Int
    }

    public let id: String
    public let category: String
    public let subcategory: String?
    public let headline: String
    public let body: String
    public let sourceTitle: String
    public let sourceURL: String
    public let quiz: Quiz?
    /// An invitation to notice or try something, shown when there is no quiz.
    public let prompt: String?
    public let evergreen: Bool?
    public let version: Int?

    public var wordCount: Int { body.split(whereSeparator: { $0 == " " || $0 == "\n" }).count }
}

/// A small optional activity, one to five minutes.
public struct MicroChallenge: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let mood: String
    public let title: String
    public let detail: String
    public let minutes: Int
}

public enum DiscoveryLibrary {
    public static let cards: [DiscoveryCard] = CoreResources.decode("discoveries") ?? []
    public static let micro: [MicroChallenge] = CoreResources.decode("micro") ?? []
    public static func card(id: String) -> DiscoveryCard? { cards.first { $0.id == id } }
    public static func microChallenge(id: String) -> MicroChallenge? { micro.first { $0.id == id } }
}

public enum Points {
    public static let sparkInteraction = 5
    public static let microChallenge = 10
}

/// Chooses the day's Spark and micro-challenge.
///
/// The choice is deterministic for a given day and seed, favours the person's
/// interests, avoids anything seen recently, and tries not to repeat
/// yesterday's category. It never invents content: when the interest pool is
/// exhausted it falls back to verified evergreen cards.
public enum SparkSelector {
    public static func pick(dayKey: String,
                            seed: String,
                            interests: [InterestChoice],
                            seen: Set<String>,
                            dismissed: Set<String>,
                            lastCategory: String?,
                            library: [DiscoveryCard] = DiscoveryLibrary.cards) -> DiscoveryCard? {
        guard !library.isEmpty else { return nil }
        var rng = SeededGenerator(string: "spark|\(dayKey)|\(seed)")
        let chosenCategories = Set(interests.map(\.category))
        let fresh = library.filter { !seen.contains($0.id) && !dismissed.contains($0.id) }

        func weight(_ card: DiscoveryCard) -> Double {
            guard let choice = interests.first(where: { $0.category == card.category }) else { return 0 }
            var w = max(0.1, choice.weight)
            if let sub = choice.subcategory, sub != "both", sub != "general", let cardSub = card.subcategory {
                w *= cardSub == sub ? 2.5 : 0.6
            }
            if card.category == lastCategory, chosenCategories.count > 1 { w *= 0.15 }
            return w
        }

        // 1. Fresh cards in the person's interests, weighted.
        let pool = fresh.filter { chosenCategories.contains($0.category) }
        if let card = weightedPick(pool, weight: weight, using: &rng) { return card }
        // 2. Fresh evergreen cards from any category.
        let evergreen = fresh.filter { $0.evergreen == true }
        if let card = evergreen.randomElement(using: &rng) { return card }
        // 3. Any fresh card.
        if let card = fresh.randomElement(using: &rng) { return card }
        // 4. Everything has been seen: revisit an evergreen card not dismissed.
        let revisit = library.filter { !dismissed.contains($0.id) && ($0.evergreen == true || chosenCategories.contains($0.category)) }
        return revisit.randomElement(using: &rng) ?? library.randomElement(using: &rng)
    }

    public static func pickMicro(dayKey: String,
                                 seed: String,
                                 interests: [InterestChoice],
                                 feeling: YearFeeling?,
                                 recent: Set<String>,
                                 avoidCategory: String?,
                                 library: [MicroChallenge] = DiscoveryLibrary.micro) -> MicroChallenge? {
        guard !library.isEmpty else { return nil }
        var rng = SeededGenerator(string: "micro|\(dayKey)|\(seed)")
        let chosen = Set(interests.map(\.category))
        let moods = Set(feeling?.favouredMoods ?? [])
        let fresh = library.filter { !recent.contains($0.id) }
        let base = fresh.isEmpty ? library : fresh
        func weight(_ m: MicroChallenge) -> Double {
            var w = 0.2
            if chosen.contains(m.category) { w += 1 }
            if m.category == "general" { w += 0.5 }
            if moods.contains(m.mood) { w *= 2 }
            if m.category == avoidCategory { w *= 0.4 }
            return w
        }
        return weightedPick(base, weight: weight, using: &rng) ?? base.randomElement(using: &rng)
    }

    static func weightedPick<T, G: RandomNumberGenerator>(_ items: [T], weight: (T) -> Double, using rng: inout G) -> T? {
        let weights = items.map { max(0, weight($0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total, using: &rng)
        for (i, w) in weights.enumerated() {
            if roll < w { return items[i] }
            roll -= w
        }
        return items.last
    }
}
