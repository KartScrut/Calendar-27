import Foundation

/// Which reusable activity interface a challenge uses.
public enum ChallengeModule: String, Codable, Sendable {
    case reflection, sudoku, timer, photos, reading, vocabulary, creative, focus
}

/// How logged activity turns into progress.
public enum ProgressMetric: String, Codable, Sendable {
    /// Number of distinct calendar days with at least one entry.
    case distinctDays
    /// Number of entries.
    case count
    /// Sum of entry amounts, where amounts are seconds and the target is minutes.
    case sumMinutes
    /// Sum of entry amounts (pages).
    case sumAmount
    /// Number of distinct `ref` values (for example distinct solved puzzle ids).
    case distinctRefs
    /// Number of entries whose amount reaches `minimumAmount` (full focus sessions).
    case qualifyingSessions
    /// Distinct words learned, plus a passed recall quiz.
    case vocabulary
}

public struct AccessibleAlternative: Codable, Equatable, Sendable {
    public let title: String
    public let detail: String
}

/// One monthly challenge as authored in the editorial catalog.
public struct ChallengeDefinition: Codable, Identifiable, Equatable, Sendable {
    public let id: String            // "2027-02"
    public let year: Int
    public let month: Int
    public let title: String
    public let tagline: String
    public let category: String
    public let story: String
    public let why: String
    public let instructions: [String]
    public let safetyNote: String?
    public let target: Double
    public let unit: String          // "days", "puzzles", "minutes", ...
    public let module: ChallengeModule
    public let metric: ProgressMetric
    public let entryKind: String     // the activity kind that counts toward progress
    public let minimumAmount: Double?
    public let prompts: [String]
    public let accessibleAlternative: AccessibleAlternative?
    public let symbol: String        // SF Symbol used as the month motif
    public let accent: String        // design-token name
    public let reflectionPrompt: String
    public let completionLine: String
    public let version: Int

    public var monthName: String { YearCalendar.monthName(month) }

    public static func id(year: Int, month: Int) -> String { "\(year)-\(YearCalendar.twoDigit(month))" }
}

/// The catalog of challenges for a year. Loaded from bundled JSON so the app
/// works offline and for guests; the server holds the same catalog behind a
/// reveal-date policy and can supply editorial updates for revealed months.
public struct ChallengeCatalog: Sendable {
    public let challenges: [ChallengeDefinition]

    public init(challenges: [ChallengeDefinition]) {
        self.challenges = challenges.sorted { $0.month < $1.month }
    }

    public static let bundled: ChallengeCatalog = {
        let list: [ChallengeDefinition] = CoreResources.decode("challenges") ?? []
        return ChallengeCatalog(challenges: list)
    }()

    public func challenge(month: Int, year: Int = 2027) -> ChallengeDefinition? {
        challenges.first { $0.month == month && $0.year == year }
    }

    public func challenge(id: String) -> ChallengeDefinition? {
        challenges.first { $0.id == id }
    }

    /// Only the challenges whose reveal date has passed. UI must use this
    /// (never `challenges`) when showing names, stories or mechanics.
    public func revealed(at now: Date, calendar: YearCalendar) -> [ChallengeDefinition] {
        challenges.filter { $0.year == calendar.year && calendar.isRevealed(month: $0.month, at: now) }
    }

    /// Applies editorial overrides fetched from the server. Completion criteria
    /// (target, metric, kind) are never overridden for a month that has started.
    public func applying(overrides: [ChallengeDefinition], at now: Date, calendar: YearCalendar) -> ChallengeCatalog {
        var merged = challenges
        for o in overrides {
            guard let i = merged.firstIndex(where: { $0.id == o.id }) else { continue }
            let current = merged[i]
            guard o.version >= current.version else { continue }
            let started = calendar.isRevealed(month: current.month, at: now)
            let criteriaChanged = o.target != current.target || o.metric != current.metric
                || o.entryKind != current.entryKind || o.module != current.module
            if started && criteriaChanged { continue }
            merged[i] = o
        }
        return ChallengeCatalog(challenges: merged)
    }
}

/// Loads JSON resources bundled with the package.
public enum CoreResources {
    public static func data(_ name: String) -> Data? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func decode<T: Decodable>(_ name: String) -> T? {
        guard let data = data(name) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
