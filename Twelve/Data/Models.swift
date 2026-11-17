import Foundation
import SwiftData
import TwelveCore

// On-device storage (SwiftData). Everything the app needs works from these
// models alone; the sync layer copies them to the server when signed in.

/// One logged piece of activity: a reflection, a photo, pages read, a timed
/// session, a learned word… Progress is always derived from these, never stored.
@Model
final class ActivityEntry {
    @Attribute(.unique) var id: UUID
    var challengeID: String
    var kind: String
    /// The calendar day (in the profile's time zone) this happened on. Fixed
    /// at creation, so later travel never moves it to another month.
    var dayKey: String
    var date: Date
    var amount: Double
    var ref: String?
    var title: String?
    var text: String?
    /// File name of a photo stored on this device only.
    var photoFile: String?
    var variant: String?
    var startedAt: Date?
    var eventsData: Data?
    /// Soft delete, so other devices learn about removals.
    var removed: Bool
    var needsSync: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), challengeID: String, kind: String, dayKey: String, date: Date, amount: Double = 1,
         ref: String? = nil, title: String? = nil, text: String? = nil, photoFile: String? = nil,
         variant: String? = nil, startedAt: Date? = nil, eventsData: Data? = nil) {
        self.id = id
        self.challengeID = challengeID
        self.kind = kind
        self.dayKey = dayKey
        self.date = date
        self.amount = amount
        self.ref = ref
        self.title = title
        self.text = text
        self.photoFile = photoFile
        self.variant = variant
        self.startedAt = startedAt
        self.eventsData = eventsData
        self.removed = false
        self.needsSync = true
        self.updatedAt = Date()
    }

    var fact: ActivityFact {
        ActivityFact(challengeID: challengeID, kind: kind, dayKey: dayKey, amount: amount, ref: ref, date: date)
    }

    static let timedKinds: Set<String> = ["plank", "walk", "focus"]
}

/// A Sudoku game in progress or solved. One per puzzle.
@Model
final class SudokuSave {
    @Attribute(.unique) var puzzleID: String
    var gameData: Data
    var solvedAt: Date?
    var solvedDayKey: String?
    var challengeID: String?
    var serverVerified: Bool
    var needsSync: Bool
    var updatedAt: Date

    init(puzzleID: String, gameData: Data) {
        self.puzzleID = puzzleID
        self.gameData = gameData
        self.serverVerified = false
        self.needsSync = true
        self.updatedAt = Date()
    }

    var game: SudokuGame? { try? JSONDecoder().decode(SudokuGame.self, from: gameData) }
}

/// What someone did with a discovery card.
@Model
final class CardInteraction {
    @Attribute(.unique) var cardID: String
    var seenDayKey: String
    var seenAt: Date
    var answeredAt: Date?
    var answeredCorrectly: Bool
    var saved: Bool
    var dismissed: Bool
    var needsSync: Bool
    var updatedAt: Date

    init(cardID: String, seenDayKey: String, seenAt: Date) {
        self.cardID = cardID
        self.seenDayKey = seenDayKey
        self.seenAt = seenAt
        self.answeredCorrectly = false
        self.saved = false
        self.dismissed = false
        self.needsSync = true
        self.updatedAt = Date()
    }
}

/// The Spark and micro-challenge chosen for a day, so they stay put all day.
@Model
final class DayPick {
    @Attribute(.unique) var dayKey: String
    var sparkID: String?
    var microID: String?
    var microDoneAt: Date?

    init(dayKey: String) { self.dayKey = dayKey }
}

/// A collected month. Created the moment a month's goal is first reached and
/// never removed, so later edits can't take an achievement away.
@Model
final class StampRecord {
    @Attribute(.unique) var month: Int
    var year: Int
    var challengeID: String
    var completedAt: Date
    /// Set once the server has independently verified the completion.
    var verifiedAt: Date?
    var reflection: String?
    var celebrated: Bool

    init(year: Int, month: Int, challengeID: String, completedAt: Date) {
        self.year = year
        self.month = month
        self.challengeID = challengeID
        self.completedAt = completedAt
        self.celebrated = false
    }
}

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var createdAt: Date

    init(title: String, author: String) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.createdAt = Date()
    }
}

struct ReminderPreferences: Codable, Equatable {
    var dailySpark = false
    var monthlyReveal = false
    var progress = false
    /// Minutes after midnight for the daily Spark.
    var dailyMinutes = 9 * 60

    var anyEnabled: Bool { dailySpark || monthlyReveal || progress }
}

/// The single local profile. Works for guests; mirrored to the server when signed in.
@Model
final class ProfileRecord {
    @Attribute(.unique) var key: String
    var displayName: String
    var timeZoneID: String
    var joinedAt: Date
    var onboardingComplete: Bool
    var feelingRaw: String?
    var interestsData: Data
    var remindersData: Data
    var vocabularyLanguage: String?
    var useAccessibleVariant: Bool
    var healthEnabled: Bool
    var hasSeenSudokuTutorial: Bool
    var revealedMonthsData: Data
    /// The account this device's data belongs to, once signed in.
    var ownerUserID: String?
    var needsSync: Bool
    var updatedAt: Date

    init(timeZoneID: String, joinedAt: Date) {
        self.key = "me"
        self.displayName = ""
        self.timeZoneID = timeZoneID
        self.joinedAt = joinedAt
        self.onboardingComplete = false
        self.interestsData = Data("[]".utf8)
        self.remindersData = (try? JSONEncoder().encode(ReminderPreferences())) ?? Data()
        self.useAccessibleVariant = false
        self.healthEnabled = false
        self.hasSeenSudokuTutorial = false
        self.revealedMonthsData = Data("[]".utf8)
        self.needsSync = true
        self.updatedAt = Date()
    }

    var interests: [InterestChoice] {
        get { (try? JSONDecoder().decode([InterestChoice].self, from: interestsData)) ?? [] }
        set { interestsData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8); touch() }
    }

    var reminders: ReminderPreferences {
        get { (try? JSONDecoder().decode(ReminderPreferences.self, from: remindersData)) ?? ReminderPreferences() }
        set { remindersData = (try? JSONEncoder().encode(newValue)) ?? Data(); touch() }
    }

    var feeling: YearFeeling? {
        get { feelingRaw.flatMap(YearFeeling.init(rawValue:)) }
        set { feelingRaw = newValue?.rawValue; touch() }
    }

    /// Months whose reveal animation has been watched.
    var revealedMonths: Set<Int> {
        get { Set((try? JSONDecoder().decode([Int].self, from: revealedMonthsData)) ?? []) }
        set { revealedMonthsData = (try? JSONEncoder().encode(newValue.sorted())) ?? Data("[]".utf8) }
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    func touch() {
        needsSync = true
        updatedAt = Date()
    }
}

enum Persistence {
    static let models: [any PersistentModel.Type] = [
        ActivityEntry.self, SudokuSave.self, CardInteraction.self, DayPick.self,
        StampRecord.self, Book.self, ProfileRecord.self,
    ]

    /// - Parameter demo: a separate store used by the debug date simulator, so
    ///   pretend progress can never mix with the real year.
    static func makeContainer(demo: Bool = false, inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(demo ? "TwelveDemo" : "Twelve", schema: schema,
                                        isStoredInMemoryOnly: inMemory, allowsSave: true,
                                        groupContainer: .none, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Never lose the ability to launch: fall back to memory and say so in the UI.
            Persistence.failedToOpen = true
            let memory = ModelConfiguration("TwelveFallback", schema: schema, isStoredInMemoryOnly: true,
                                            allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }

    static var failedToOpen = false
}
