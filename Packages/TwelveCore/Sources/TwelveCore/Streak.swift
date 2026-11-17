import Foundation

/// How a month tile should be presented.
public enum MonthState: String, Equatable, Sendable {
    /// Not yet revealed.
    case sealed
    /// Revealed, still open, not complete.
    case active
    /// Primary challenge completed (in an open or closed month).
    case completed
    /// Closed without completion. Shown neutrally, as an archive.
    case archived
    /// Closed before the person joined. Never counted as missed.
    case beforeJoining
}

public struct YearSummary: Equatable, Sendable {
    /// Total primary challenges completed. Never decreases.
    public let monthsCompleted: Int
    /// Consecutive eligible months completed, ending at the present.
    public let currentStreak: Int
    public let bestStreak: Int
    /// States for months 1...12 (index 0 = January).
    public let states: [MonthState]

    public func state(month: Int) -> MonthState {
        (1...12).contains(month) ? states[month - 1] : .sealed
    }
}

public enum StreakCalculator {
    /// - Parameters:
    ///   - completed: months (1...12) whose primary challenge was completed.
    ///   - joinMonth: the first month the person was eligible for (month they
    ///     started, or 1 if they joined before the year began).
    ///   - currentMonth: the month in progress, or nil before/after the year.
    ///   - yearEnded: true once the year is over.
    public static func summary(completed: Set<Int>, joinMonth: Int, currentMonth: Int?, yearEnded: Bool) -> YearSummary {
        let join = min(max(joinMonth, 1), 12)
        var states: [MonthState] = []
        for m in 1...12 {
            let closed = yearEnded || (currentMonth.map { m < $0 } ?? false)
            let isCurrent = currentMonth == m
            if completed.contains(m) && (closed || isCurrent) {
                states.append(.completed)
            } else if isCurrent {
                states.append(.active)
            } else if closed {
                states.append(m < join ? .beforeJoining : .archived)
            } else {
                states.append(.sealed)
            }
        }

        // Best streak: longest run of completed months among eligible ones.
        var best = 0, run = 0
        for m in join...12 {
            if states[m - 1] == .completed { run += 1; best = max(best, run) } else { run = 0 }
        }

        // Current streak: walk backwards from the latest month that has started.
        // An open, unfinished current month does not break the streak — it simply
        // has not added to it yet. A closed, eligible, unfinished month does.
        var current = 0
        let last: Int? = yearEnded ? 12 : currentMonth
        if let last {
            var m = last
            if states[m - 1] == .active { m -= 1 }
            while m >= join, states[m - 1] == .completed {
                current += 1
                m -= 1
            }
        }

        let total = states.filter { $0 == .completed }.count
        return YearSummary(monthsCompleted: total, currentStreak: current, bestStreak: best, states: states)
    }

    /// The first eligible month for someone who joined at `joinDate`.
    public static func joinMonth(joinDate: Date, calendar: YearCalendar) -> Int {
        switch calendar.phase(at: joinDate) {
        case .prelaunch: return 1
        case .active(let m, _): return m
        case .ended: return 12
        }
    }
}
