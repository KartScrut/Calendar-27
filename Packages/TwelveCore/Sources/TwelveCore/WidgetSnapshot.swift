import Foundation

/// Identifiers shared by the app and its extensions.
public enum AppGroup {
    public static let identifier = "group.com.twelve.app"
    public static let widgetKind = "TwelveCalendarWidget"
    public static let lockWidgetKind = "TwelveLockWidget"
    public static let snapshotKey = "widget.snapshot.v1"
    public static let timerKey = "timer.active.v1"
    public static let pendingMicroKey = "micro.pending.v1"

    public static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

/// Deep links understood by the app.
public enum DeepLink: String, CaseIterable, Sendable {
    case today, challenge, spark, year, timer

    public var url: URL { URL(string: "twelve://\(rawValue)")! }

    public init?(url: URL) {
        guard url.scheme == "twelve", let host = url.host, let link = DeepLink(rawValue: host) else { return nil }
        self = link
    }

    /// Quick-action type identifiers map 1:1 to deep links.
    public init?(shortcutType: String) {
        guard let last = shortcutType.split(separator: ".").last, let link = DeepLink(rawValue: String(last)) else { return nil }
        self = link
    }
}

/// Everything the widgets need, written by the app into the App Group.
/// Widgets never touch the database or the network.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var year: Int
    public var timeZoneID: String
    public var completedMonths: [Int]
    public var streak: Int
    /// Current challenge, only once revealed. Nil before the year starts.
    public var challengeMonth: Int?
    public var challengeTitle: String?
    public var challengeProgressLabel: String?
    public var challengeFraction: Double
    public var challengeComplete: Bool
    public var sparkHeadline: String?
    public var microID: String?
    public var microTitle: String?
    public var microDoneDayKey: String?
    public var microDayKey: String?
    public var onboarded: Bool
    public var updatedAt: Date

    public init(year: Int = 2027, timeZoneID: String = TimeZone.current.identifier, completedMonths: [Int] = [],
                streak: Int = 0, challengeMonth: Int? = nil, challengeTitle: String? = nil,
                challengeProgressLabel: String? = nil, challengeFraction: Double = 0, challengeComplete: Bool = false,
                sparkHeadline: String? = nil, microID: String? = nil, microTitle: String? = nil,
                microDoneDayKey: String? = nil, microDayKey: String? = nil, onboarded: Bool = false,
                updatedAt: Date = Date()) {
        self.year = year
        self.timeZoneID = timeZoneID
        self.completedMonths = completedMonths
        self.streak = streak
        self.challengeMonth = challengeMonth
        self.challengeTitle = challengeTitle
        self.challengeProgressLabel = challengeProgressLabel
        self.challengeFraction = challengeFraction
        self.challengeComplete = challengeComplete
        self.sparkHeadline = sparkHeadline
        self.microID = microID
        self.microTitle = microTitle
        self.microDoneDayKey = microDoneDayKey
        self.microDayKey = microDayKey
        self.onboarded = onboarded
        self.updatedAt = updatedAt
    }

    public var completedCount: Int { Set(completedMonths).count }

    /// "02 / 12"
    public var countLabel: String { "\(YearCalendar.twoDigit(completedCount)) / 12" }

    /// "1 month complete" / "3 months complete"
    public var completeLabel: String {
        completedCount == 1 ? "1 month complete" : "\(completedCount) months complete"
    }

    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> WidgetSnapshot {
        guard let data = defaults.data(forKey: AppGroup.snapshotKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    public func save(to defaults: UserDefaults = AppGroup.defaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: AppGroup.snapshotKey) }
    }

    /// Whether the challenge details in this snapshot are still valid for
    /// `date`. A snapshot written in January must not show January's challenge
    /// (or leak nothing new) once February begins.
    public func challengeIsCurrent(at date: Date) -> Bool {
        guard let m = challengeMonth, let tz = TimeZone(identifier: timeZoneID) else { return false }
        return YearCalendar(year: year, timeZone: tz).currentMonth(at: date) == m
    }

    public static let preview = WidgetSnapshot(completedMonths: [1, 2], streak: 2, challengeMonth: 3,
                                               challengeTitle: "Build your core", challengeProgressLabel: "12 of 30 minutes",
                                               challengeFraction: 0.4, sparkHeadline: "Why the save icon is still a floppy disk",
                                               microID: "preview", microTitle: "Find a typeface you'd change",
                                               microDayKey: "2027-03-09", onboarded: true)
}

/// Stores the active timer session in the App Group so the app, the Live
/// Activity buttons and a relaunch after termination all see the same truth.
public enum TimerStore {
    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> TimerSession? {
        guard let data = defaults.data(forKey: AppGroup.timerKey) else { return nil }
        return try? JSONDecoder().decode(TimerSession.self, from: data)
    }

    public static func save(_ session: TimerSession?, to defaults: UserDefaults = AppGroup.defaults) {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: AppGroup.timerKey)
        } else {
            defaults.removeObject(forKey: AppGroup.timerKey)
        }
    }
}
