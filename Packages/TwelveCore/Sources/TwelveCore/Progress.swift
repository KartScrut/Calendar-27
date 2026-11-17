import Foundation

/// The minimal facts about a logged activity that progress maths needs.
/// The app maps its stored entries to these; the server recomputes the same
/// rules in SQL before it grants an achievement.
public struct ActivityFact: Equatable, Sendable {
    public let challengeID: String
    public let kind: String
    public let dayKey: String
    public let amount: Double
    public let ref: String?
    public let date: Date

    public init(challengeID: String, kind: String, dayKey: String, amount: Double = 1, ref: String? = nil, date: Date) {
        self.challengeID = challengeID
        self.kind = kind
        self.dayKey = dayKey
        self.amount = amount
        self.ref = ref
        self.date = date
    }
}

public struct ChallengeProgress: Equatable, Sendable {
    public let value: Double
    public let target: Double
    public let isComplete: Bool
    /// When the goal was reached (the instant of the entry that crossed the line).
    public let completedAt: Date?
    /// Extra state for vocabulary: whether the recall quiz was passed.
    public let quizPassed: Bool

    public var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, value / target))
    }

    public var remaining: Double { max(0, target - value) }

    public static func empty(target: Double) -> ChallengeProgress {
        ChallengeProgress(value: 0, target: target, isComplete: false, completedAt: nil, quizPassed: false)
    }
}

public enum ProgressCalculator {
    public static let quizPassKind = "quiz_pass"

    /// Upper bounds for a single logged amount. Anything outside is ignored, so a
    /// corrupted or tampered entry cannot complete a month on its own.
    public static func isPlausible(kind: String, amount: Double) -> Bool {
        guard amount.isFinite, amount >= 0 else { return false }
        switch kind {
        case "plank": return amount <= 20 * 60
        case "walk": return amount <= 6 * 3600
        case "focus": return amount <= 10 * 60 + 1
        case "reading": return amount >= 1 && amount <= 500
        default: return amount <= 1_000_000
        }
    }

    public static func progress(for challenge: ChallengeDefinition,
                                facts: [ActivityFact],
                                calendar: YearCalendar) -> ChallengeProgress {
        // Only activity dated inside the challenge's own month counts.
        let inMonth = facts
            .filter { $0.challengeID == challenge.id && calendar.month(ofDayKey: $0.dayKey) == challenge.month }
            .filter { isPlausible(kind: $0.kind, amount: $0.amount) }
            .sorted { $0.date < $1.date }
        let relevant = inMonth.filter { $0.kind == challenge.entryKind }
        let target = challenge.target

        var value = 0.0
        var completedAt: Date?
        var quizPassed = false

        func reach(_ date: Date) { if completedAt == nil, value >= target { completedAt = date } }

        switch challenge.metric {
        case .distinctDays:
            var days = Set<String>()
            for f in relevant where days.insert(f.dayKey).inserted {
                value = Double(days.count); reach(f.date)
            }
        case .count:
            for f in relevant { value += 1; reach(f.date) }
        case .sumMinutes:
            var seconds = 0.0
            for f in relevant {
                seconds += f.amount
                value = seconds / 60
                reach(f.date)
            }
        case .sumAmount:
            for f in relevant { value += f.amount; reach(f.date) }
        case .distinctRefs:
            var refs = Set<String>()
            for f in relevant {
                guard let r = f.ref, !r.isEmpty, refs.insert(r).inserted else { continue }
                value = Double(refs.count); reach(f.date)
            }
        case .qualifyingSessions:
            let minimum = challenge.minimumAmount ?? 0
            for f in relevant where f.amount >= minimum { value += 1; reach(f.date) }
        case .vocabulary:
            var words = Set<String>()
            for f in relevant {
                guard let r = f.ref, !r.isEmpty else { continue }
                words.insert(r)
            }
            value = min(target, Double(words.count))
            if let pass = inMonth.first(where: { $0.kind == quizPassKind }), value >= target {
                quizPassed = true
                completedAt = pass.date
            }
            let complete = quizPassed
            return ChallengeProgress(value: value, target: target, isComplete: complete,
                                     completedAt: complete ? completedAt : nil, quizPassed: quizPassed)
        }

        let complete = value >= target
        return ChallengeProgress(value: value, target: target, isComplete: complete,
                                 completedAt: complete ? completedAt : nil, quizPassed: false)
    }

    /// "07:24" style label for second counts.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h):\(YearCalendar.twoDigit(m)):\(YearCalendar.twoDigit(s))" }
        return "\(YearCalendar.twoDigit(m)):\(YearCalendar.twoDigit(s))"
    }

    /// Human label such as "3 of 5 puzzles" or "12 of 30 minutes".
    public static func label(for challenge: ChallengeDefinition, progress: ChallengeProgress) -> String {
        let v = Int(progress.value.rounded(.down))
        let t = Int(challenge.target)
        return "\(min(v, t)) of \(t) \(challenge.unit)"
    }
}
