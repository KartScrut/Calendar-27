import Foundation

/// Where "now" falls relative to the product year.
public enum YearPhase: Equatable, Sendable {
    /// Before 1 January. `days` is whole days remaining until the year begins.
    case prelaunch(days: Int)
    /// Inside the year. Month is 1...12, day is the day of the month.
    case active(month: Int, day: Int)
    /// After 31 December.
    case ended
}

/// All date maths for one product year, in the user's chosen calendar time zone.
///
/// The time zone is fixed in the profile (not read from the device each time) so
/// travelling never rewrites history: every logged activity stores the `dayKey`
/// it happened on, and month membership is decided from that key alone.
public struct YearCalendar: Equatable, Sendable {
    public let year: Int
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(year: Int = 2027, timeZone: TimeZone = .current) {
        self.year = year
        self.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday
        self.calendar = cal
    }

    public static func == (lhs: YearCalendar, rhs: YearCalendar) -> Bool {
        lhs.year == rhs.year && lhs.timeZone.identifier == rhs.timeZone.identifier
    }

    // MARK: Keys

    /// "2027-03-09" for the given instant in the calendar time zone.
    public func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Self.key(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    public static func key(year: Int, month: Int, day: Int) -> String {
        let y = String(year)
        let m = month < 10 ? "0\(month)" : "\(month)"
        let d = day < 10 ? "0\(day)" : "\(day)"
        return "\(y)-\(m)-\(d)"
    }

    public func dayKey(month: Int, day: Int) -> String {
        Self.key(year: year, month: month, day: day)
    }

    /// Parses a day key. Returns nil for malformed keys.
    public static func parse(dayKey: String) -> (year: Int, month: Int, day: Int)? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return (y, m, d)
    }

    /// The month (1...12) a day key belongs to, or nil if it is outside this year.
    public func month(ofDayKey key: String) -> Int? {
        guard let p = Self.parse(dayKey: key), p.year == year else { return nil }
        return p.month
    }

    // MARK: Instants

    public func date(month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    public var yearStart: Date { date(month: 1, day: 1) }

    public var yearEnd: Date {
        var c = DateComponents()
        c.year = year + 1; c.month = 1; c.day = 1
        return calendar.date(from: c) ?? Date.distantFuture
    }

    /// The instant a month's challenge is revealed: local midnight on the 1st.
    public func revealDate(month: Int) -> Date { date(month: month, day: 1) }

    /// The first instant after the month closes.
    public func closeDate(month: Int) -> Date {
        month >= 12 ? yearEnd : date(month: month + 1, day: 1)
    }

    // MARK: Phase

    public func phase(at now: Date) -> YearPhase {
        if now < yearStart {
            let startOfToday = calendar.startOfDay(for: now)
            let days = calendar.dateComponents([.day], from: startOfToday, to: yearStart).day ?? 0
            return .prelaunch(days: max(days, 1))
        }
        if now >= yearEnd { return .ended }
        let c = calendar.dateComponents([.month, .day], from: now)
        return .active(month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Current month if the year is running, else nil.
    public func currentMonth(at now: Date) -> Int? {
        if case .active(let m, _) = phase(at: now) { return m }
        return nil
    }

    public func isRevealed(month: Int, at now: Date) -> Bool {
        now >= revealDate(month: month)
    }

    public func isClosed(month: Int, at now: Date) -> Bool {
        now >= closeDate(month: month)
    }

    // MARK: Layout helpers

    public func daysIn(month: Int) -> Int {
        let d = date(month: month, day: 1)
        return calendar.range(of: .day, in: .month, for: d)?.count ?? 30
    }

    /// Number of blank cells before day 1 in a Monday-first grid (0...6).
    public func leadingBlanks(month: Int) -> Int {
        let weekday = calendar.component(.weekday, from: date(month: month, day: 1)) // 1 = Sunday
        return (weekday + 5) % 7
    }

    public var daysInYear: Int {
        calendar.dateComponents([.day], from: yearStart, to: yearEnd).day ?? 365
    }

    /// 1-based day of the year, clamped to the year.
    public func dayOfYear(at now: Date) -> Int {
        if now < yearStart { return 0 }
        if now >= yearEnd { return daysInYear }
        let d = calendar.dateComponents([.day], from: yearStart, to: calendar.startOfDay(for: now)).day ?? 0
        return d + 1
    }

    /// Fraction of the year that has elapsed, 0...1.
    public func yearProgress(at now: Date) -> Double {
        Double(dayOfYear(at: now)) / Double(daysInYear)
    }

    /// Weekday index for a date in this time zone, Monday = 0 ... Sunday = 6.
    public func weekdayIndex(for date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    public func components(for date: Date) -> (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? year, c.month ?? 1, c.day ?? 1)
    }

    public func startOfNextDay(after date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }

    public static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                    "August", "September", "October", "November", "December"]
    public static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    public static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    public static func monthName(_ month: Int) -> String {
        (1...12).contains(month) ? monthNames[month - 1] : ""
    }

    public static func twoDigit(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

/// A small deterministic generator (SplitMix64) so "today's" picks are stable
/// for a given day and user without storing randomness.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public init(string: String) {
        // FNV-1a, stable across launches and platforms (unlike Hasher).
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in string.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01B3 }
        self.init(seed: h)
    }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
