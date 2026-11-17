import Foundation
import Observation
import SwiftData
import TwelveCore
import UIKit
import WidgetKit

/// The app's single source of truth for screens. It owns the stored data,
/// derives everything else (progress, streaks, today's picks) from it, and is
/// the only place that decides when a month has been completed.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case today, calendar, collection, profile }

    enum Sheet: Identifiable, Equatable {
        case challenge(month: Int)
        case spark
        case account
        case yearInReview

        var id: String {
            switch self {
            case .challenge(let m): return "challenge-\(m)"
            case .spark: return "spark"
            case .account: return "account"
            case .yearInReview: return "review"
            }
        }
    }

    static let year = 2027

    // Services
    private(set) var store: DataStore
    let auth: AuthService
    let sync: SyncService
    let timer: TimerController
    let notifications = NotificationService()

    // Stored state
    private(set) var profile: ProfileRecord
    private(set) var catalog: ChallengeCatalog

    // Derived state (recomputed by `refresh`)
    private(set) var now: Date
    private(set) var calendar: YearCalendar
    private(set) var phase: YearPhase
    private(set) var summary: YearSummary
    private(set) var progress: [Int: ChallengeProgress] = [:]
    private(set) var spark: DiscoveryCard?
    private(set) var micro: MicroChallenge?
    private(set) var microDone = false
    private(set) var points = 0
    private(set) var revision = 0

    // Navigation
    var tab: Tab = .today
    var sheet: Sheet?
    var showYearOverview = false
    var startTimerOnOpen = false
    /// Set when a month has just been completed; drives the celebration.
    var celebration: ChallengeDefinition?

    let isInMemory: Bool
    var isDemo: Bool { AppClock.isSimulated }
    var storageFailed: Bool { Persistence.failedToOpen }

    init(inMemory: Bool = false, auth: AuthService? = nil) {
        self.isInMemory = inMemory
        let store = DataStore(container: Persistence.makeContainer(demo: AppClock.isSimulated && !inMemory, inMemory: inMemory))
        self.store = store
        self.auth = auth ?? AuthService()
        self.sync = SyncService()
        self.timer = TimerController()
        let now = AppClock.now
        self.now = now
        let profile = store.profile(now: now)
        self.profile = profile
        self.catalog = EditorialCache.load() ?? .bundled
        let cal = YearCalendar(year: Self.year, timeZone: profile.timeZone)
        self.calendar = cal
        self.phase = cal.phase(at: now)
        self.summary = StreakCalculator.summary(completed: [], joinMonth: 1, currentMonth: nil, yearEnded: false)
        sync.app = self
        timer.app = self
        refresh()
    }

    // MARK: Convenience

    var currentMonth: Int? { calendar.currentMonth(at: now) }
    var todayKey: String { calendar.dayKey(for: now) }
    var isOnboarded: Bool { profile.onboardingComplete }

    var currentChallenge: ChallengeDefinition? {
        guard let m = currentMonth else { return nil }
        return catalog.challenge(month: m, year: Self.year)
    }

    /// A challenge, only if its month has been revealed. Screens must use this.
    func revealedChallenge(month: Int) -> ChallengeDefinition? {
        guard calendar.isRevealed(month: month, at: now) else { return nil }
        return catalog.challenge(month: month, year: Self.year)
    }

    func progress(for challenge: ChallengeDefinition) -> ChallengeProgress {
        progress[challenge.month] ?? .empty(target: challenge.target)
    }

    /// New activity can only be logged for the month that is in progress.
    func isOpen(_ challenge: ChallengeDefinition) -> Bool {
        isOnboarded && currentMonth == challenge.month && challenge.year == Self.year
    }

    func hasWatchedReveal(month: Int) -> Bool { profile.revealedMonths.contains(month) }

    func markRevealWatched(month: Int) {
        var set = profile.revealedMonths
        guard set.insert(month).inserted else { return }
        profile.revealedMonths = set
        store.save()
        revision += 1
    }

    // MARK: Refresh

    /// Recomputes everything derived. Cheap enough to call after every change.
    func refresh() {
        now = AppClock.now
        calendar = YearCalendar(year: Self.year, timeZone: profile.timeZone)
        phase = calendar.phase(at: now)

        let facts = store.facts()
        var newProgress: [Int: ChallengeProgress] = [:]
        for challenge in catalog.revealed(at: now, calendar: calendar) {
            let p = ProgressCalculator.progress(for: challenge, facts: facts, calendar: calendar)
            newProgress[challenge.month] = p
            // Award the stamp the moment the goal is reached. One stamp per
            // month, ever: awarding is idempotent.
            if p.isComplete, isOnboarded {
                let result = store.awardStamp(year: Self.year, month: challenge.month, challengeID: challenge.id,
                                              completedAt: p.completedAt ?? now)
                if result.isNew, challenge.month == currentMonth {
                    celebration = challenge
                }
            }
        }
        progress = newProgress

        let completed = Set(store.stamps().filter { $0.year == Self.year }.map(\.month))
        let join = StreakCalculator.joinMonth(joinDate: profile.joinedAt, calendar: calendar)
        var yearEnded = false
        if case .ended = phase { yearEnded = true }
        summary = StreakCalculator.summary(completed: completed, joinMonth: join, currentMonth: currentMonth, yearEnded: yearEnded)

        refreshDailyPicks()
        points = store.interactions().filter { $0.answeredAt != nil }.count * Points.sparkInteraction
            + store.dayPicks().filter { $0.microDoneAt != nil }.count * Points.microChallenge
        revision += 1
        writeWidgetSnapshot()
        if isOnboarded { notifications.reschedule(for: self) }
    }

    private func refreshDailyPicks() {
        guard isOnboarded, currentMonth != nil || phase == .ended else {
            spark = nil; micro = nil; microDone = false
            return
        }
        let key = todayKey
        let pick = store.dayPick(key)
        let interactions = store.interactions()
        let seed = profile.joinedAt.timeIntervalSince1970.description

        if pick.sparkID == nil || DiscoveryLibrary.card(id: pick.sparkID ?? "") == nil {
            let seen = Set(interactions.map(\.cardID))
            let dismissed = Set(interactions.filter(\.dismissed).map(\.cardID))
            let yesterday = store.dayPicks().last { $0.dayKey < key }?.sparkID
            let lastCategory = yesterday.flatMap { DiscoveryLibrary.card(id: $0)?.category }
            pick.sparkID = SparkSelector.pick(dayKey: key, seed: seed, interests: profile.interests, seen: seen,
                                              dismissed: dismissed, lastCategory: lastCategory)?.id
        }
        spark = pick.sparkID.flatMap(DiscoveryLibrary.card(id:))

        if pick.microID == nil || DiscoveryLibrary.microChallenge(id: pick.microID ?? "") == nil {
            let recent = Set(store.dayPicks().suffix(14).compactMap(\.microID))
            pick.microID = SparkSelector.pickMicro(dayKey: key, seed: seed, interests: profile.interests,
                                                   feeling: profile.feeling, recent: recent,
                                                   avoidCategory: spark?.category)?.id
        }
        micro = pick.microID.flatMap(DiscoveryLibrary.microChallenge(id:))

        // A tap on the widget's button, waiting to be recorded.
        let inbox = MicroInbox.load()
        if let tapped = inbox[key], tapped == pick.microID, pick.microDoneAt == nil {
            pick.microDoneAt = now
        }
        if !inbox.isEmpty { MicroInbox.clear() }
        microDone = pick.microDoneAt != nil
        store.save()
    }

    private var lastSnapshot: WidgetSnapshot?

    private func writeWidgetSnapshot() {
        guard !isInMemory else { return }
        var snap = WidgetSnapshot(year: Self.year, timeZoneID: profile.timeZoneID,
                                  completedMonths: summary.states.enumerated().filter { $0.element == .completed }.map { $0.offset + 1 },
                                  streak: summary.currentStreak, onboarded: isOnboarded, updatedAt: now)
        if isOnboarded, let c = currentChallenge, hasWatchedReveal(month: c.month) {
            let p = progress(for: c)
            snap.challengeMonth = c.month
            snap.challengeTitle = c.title
            snap.challengeProgressLabel = ProgressCalculator.label(for: c, progress: p)
            snap.challengeFraction = p.fraction
            snap.challengeComplete = summary.state(month: c.month) == .completed
        } else if isOnboarded, let m = currentMonth {
            // Arrived but not yet opened: say so without giving the surprise away.
            snap.challengeMonth = m
            snap.challengeTitle = "\(YearCalendar.monthName(m))'s challenge is ready"
            snap.challengeProgressLabel = "Open to reveal"
        }
        snap.sparkHeadline = spark?.headline
        snap.microID = micro?.id
        snap.microTitle = micro?.title
        snap.microDayKey = todayKey
        snap.microDoneDayKey = microDone ? todayKey : nil
        var comparable = snap
        comparable.updatedAt = lastSnapshot?.updatedAt ?? snap.updatedAt
        if comparable != lastSnapshot {
            snap.save()
            lastSnapshot = snap
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Logging activity

    /// Records activity toward the month in progress. Returns nil (and stores
    /// nothing) if the challenge isn't open — for example before the year begins.
    @discardableResult
    func log(_ challenge: ChallengeDefinition, kind: String? = nil, amount: Double = 1, ref: String? = nil,
             title: String? = nil, text: String? = nil, photoFile: String? = nil, variant: String? = nil,
             startedAt: Date? = nil, eventsData: Data? = nil, id: UUID = UUID()) -> ActivityEntry? {
        let kind = kind ?? challenge.entryKind
        let moment = AppClock.now
        guard isOpen(challenge), calendar.currentMonth(at: moment) == challenge.month,
              ProgressCalculator.isPlausible(kind: kind, amount: amount) else { return nil }
        if store.entry(id: id) != nil { return nil } // the same event delivered twice
        let entry = ActivityEntry(id: id, challengeID: challenge.id, kind: kind, dayKey: calendar.dayKey(for: moment),
                                  date: moment, amount: amount, ref: ref, title: title, text: text,
                                  photoFile: photoFile, variant: variant, startedAt: startedAt, eventsData: eventsData)
        store.add(entry)
        refresh()
        sync.schedule()
        return entry
    }

    func remove(_ entry: ActivityEntry) {
        store.remove(entry)
        refresh()
        sync.schedule()
    }

    func update(_ entry: ActivityEntry, text: String?, title: String? = nil) {
        store.update(entry, text: text, title: title)
        revision += 1
        sync.schedule()
    }

    func entries(for challenge: ChallengeDefinition, kind: String? = nil) -> [ActivityEntry] {
        store.entries(challengeID: challenge.id, kind: kind ?? challenge.entryKind)
    }

    /// Saves a Sudoku game. A solved board counts once, for the open month only.
    func saveSudoku(_ game: SudokuGame) {
        let moment = AppClock.now
        var challengeID: String?
        if let c = currentChallenge, c.module == .sudoku, isOpen(c) { challengeID = c.id }
        store.saveSudoku(game, dayKey: calendar.dayKey(for: moment), challengeID: challengeID, now: moment)
        if game.isSolved {
            refresh()
            sync.schedule()
        }
    }

    func saveReflection(month: Int, text: String) {
        guard let stamp = store.stamp(month: month) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stamp.reflection = trimmed.isEmpty ? nil : String(trimmed.prefix(2000))
        store.save()
        revision += 1
    }

    // MARK: Discoveries

    func interaction(for card: DiscoveryCard) -> CardInteraction {
        store.interaction(cardID: card.id, dayKey: todayKey, now: now)
    }

    /// Answering earns points once per card, right or wrong: the reward is
    /// for engaging, and it cannot be repeated.
    func answer(_ card: DiscoveryCard, option: Int) -> Bool {
        let i = interaction(for: card)
        let correct = card.quiz?.answer == option
        if i.answeredAt == nil {
            i.answeredAt = now
            i.answeredCorrectly = correct
            i.needsSync = true
            i.updatedAt = Date()
            store.save()
            refresh()
            sync.schedule()
        }
        return correct
    }

    /// For cards with a prompt instead of a quiz: "I did this".
    func acknowledge(_ card: DiscoveryCard) {
        _ = answer(card, option: -1)
    }

    func toggleSaved(_ card: DiscoveryCard) {
        let i = interaction(for: card)
        i.saved.toggle()
        i.needsSync = true
        i.updatedAt = Date()
        store.save()
        revision += 1
        sync.schedule()
    }

    /// "Not interested": hide this card for good and choose another for today.
    func dismiss(_ card: DiscoveryCard) {
        let i = interaction(for: card)
        i.dismissed = true
        i.saved = false
        i.needsSync = true
        i.updatedAt = Date()
        let pick = store.dayPick(todayKey)
        if pick.sparkID == card.id { pick.sparkID = nil }
        store.save()
        refresh()
        sync.schedule()
    }

    var savedCards: [DiscoveryCard] {
        store.interactions().filter(\.saved).sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { DiscoveryLibrary.card(id: $0.cardID) }
    }

    func completeMicro() {
        let pick = store.dayPick(todayKey)
        guard pick.microDoneAt == nil, pick.microID != nil else { return }
        pick.microDoneAt = now
        store.save()
        refresh()
    }

    // MARK: Profile

    func updateProfile(_ change: (ProfileRecord) -> Void) {
        change(profile)
        profile.touch()
        store.save()
        refresh()
        sync.schedule()
    }

    func finishOnboarding() {
        profile.onboardingComplete = true
        profile.joinedAt = AppClock.now
        profile.timeZoneID = TimeZone.current.identifier
        profile.touch()
        store.save()
        refresh()
        sync.schedule()
    }

    // MARK: Accounts

    /// Called after a successful sign-in. Guest progress on this device is
    /// uploaded and merged; nothing already in the account is overwritten.
    /// Returns a message if the sign-in can't be used on this device.
    func didSignIn() async -> String? {
        guard let userID = auth.userID else { return nil }
        if let owner = profile.ownerUserID, owner != userID {
            // This device's data belongs to someone else. Never upload it to
            // a different account.
            await auth.signOut()
            return "This iPhone holds progress from a different account. Sign in to that account, or choose Erase This iPhone in Profile first."
        }
        if profile.ownerUserID == nil {
            profile.ownerUserID = userID
            store.markAllForSync()
            profile.touch()
            store.save()
        }
        refresh()
        await sync.syncNow()
        return nil
    }

    /// Signs out. Progress stays on this iPhone (including photos, which are
    /// never uploaded) and is backed up again at the next sign-in.
    func signOut() async {
        await sync.syncNow()
        await auth.signOut()
        refresh()
    }

    func deleteAccount() async throws {
        try await auth.deleteAccount()
        eraseDevice()
    }

    /// Removes everything from this iPhone and starts over.
    func eraseDevice() {
        notifications.cancelAll()
        store.eraseEverything()
        EditorialCache.clear()
        catalog = .bundled
        profile = store.profile(now: AppClock.now)
        celebration = nil
        sheet = nil
        tab = .today
        refresh()
    }

    func exportFile() -> URL? {
        let data = store.exportJSON(profile: profile)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TWELVE-export.json")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    func applyEditorial(_ overrides: [ChallengeDefinition]) {
        let merged = ChallengeCatalog.bundled.applying(overrides: overrides, at: now, calendar: calendar)
        catalog = merged
        EditorialCache.save(overrides)
        refresh()
    }

    // MARK: Deep links

    func open(_ link: DeepLink) {
        guard isOnboarded else { return }
        switch link {
        case .today:
            sheet = nil; tab = .today
        case .year:
            sheet = nil; tab = .calendar; showYearOverview = true
        case .spark:
            tab = .today
            sheet = spark == nil ? nil : .spark
        case .challenge, .timer:
            tab = .today
            if let c = currentChallenge {
                startTimerOnOpen = link == .timer && (c.module == .timer || c.module == .focus) && hasWatchedReveal(month: c.month)
                sheet = .challenge(month: c.month)
            }
        }
    }

    // MARK: Demo (debug builds only)

    #if DEBUG
    /// Jump to any date to preview the year. Uses a separate database.
    func simulate(date: Date?) {
        let interests = profile.interests
        let feeling = profile.feeling
        AppClock.simulate(date)
        store = DataStore(container: Persistence.makeContainer(demo: date != nil, inMemory: isInMemory))
        profile = store.profile(now: AppClock.now)
        if date != nil, !profile.onboardingComplete {
            profile.onboardingComplete = true
            profile.joinedAt = YearCalendar(year: Self.year, timeZone: profile.timeZone).yearStart
            profile.interests = interests.isEmpty ? [InterestChoice(category: "design"), InterestChoice(category: "science")] : interests
            profile.feeling = feeling
            store.save()
        }
        celebration = nil
        sheet = nil
        refresh()
    }

    /// Stamps every month before the simulated one, to preview a fuller collection.
    func demoCompleteEarlierMonths() {
        guard isDemo, let m = currentMonth, m > 1 else { return }
        for month in 1..<m {
            if let c = catalog.challenge(month: month) {
                store.awardStamp(year: Self.year, month: month, challengeID: c.id,
                                 completedAt: calendar.date(month: month, day: 20, hour: 18))
            }
        }
        refresh()
    }

    func demoReset() {
        guard isDemo else { return }
        let joined = profile.joinedAt
        let interests = profile.interests
        store.eraseEverything()
        profile = store.profile(now: AppClock.now)
        profile.onboardingComplete = true
        profile.joinedAt = joined
        profile.interests = interests
        store.save()
        refresh()
    }
    #endif
}

/// Editorial updates fetched from the server, kept for offline use.
enum EditorialCache {
    private static let key = "editorial.overrides.v1"

    static func save(_ overrides: [ChallengeDefinition]) {
        if let data = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func load() -> ChallengeCatalog? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let overrides = try? JSONDecoder().decode([ChallengeDefinition].self, from: data), !overrides.isEmpty else { return nil }
        let cal = YearCalendar(year: AppModel.year, timeZone: .current)
        return ChallengeCatalog.bundled.applying(overrides: overrides, at: AppClock.now, calendar: cal)
    }
}
