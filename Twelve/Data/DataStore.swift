import Foundation
import SwiftData
import TwelveCore

/// The only place that reads and writes the on-device database.
@MainActor
final class DataStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    func save() {
        do { try context.save() } catch { Log.error("save failed: \(error)") }
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Profile

    func profile(now: Date) -> ProfileRecord {
        if let p = fetch(FetchDescriptor<ProfileRecord>()).first { return p }
        let p = ProfileRecord(timeZoneID: TimeZone.current.identifier, joinedAt: now)
        context.insert(p)
        save()
        return p
    }

    // MARK: Activity

    func entries(includeRemoved: Bool = false) -> [ActivityEntry] {
        let all = fetch(FetchDescriptor<ActivityEntry>(sortBy: [SortDescriptor(\.date)]))
        return includeRemoved ? all : all.filter { !$0.removed }
    }

    func entries(challengeID: String, kind: String? = nil) -> [ActivityEntry] {
        entries().filter { $0.challengeID == challengeID && (kind == nil || $0.kind == kind) }
    }

    func entry(id: UUID) -> ActivityEntry? {
        fetch(FetchDescriptor<ActivityEntry>(predicate: #Predicate { $0.id == id })).first
    }

    @discardableResult
    func add(_ entry: ActivityEntry) -> ActivityEntry {
        context.insert(entry)
        save()
        return entry
    }

    func remove(_ entry: ActivityEntry) {
        entry.removed = true
        entry.needsSync = true
        entry.updatedAt = Date()
        if let file = entry.photoFile { PhotoStore.delete(file) }
        entry.photoFile = nil
        save()
    }

    func update(_ entry: ActivityEntry, text: String?, title: String? = nil) {
        entry.text = text
        if let title { entry.title = title }
        entry.needsSync = true
        entry.updatedAt = Date()
        save()
    }

    // MARK: Sudoku

    func sudokuSaves() -> [SudokuSave] { fetch(FetchDescriptor<SudokuSave>()) }

    func sudokuSave(puzzleID: String) -> SudokuSave? {
        fetch(FetchDescriptor<SudokuSave>(predicate: #Predicate { $0.puzzleID == puzzleID })).first
    }

    /// Persists a game. Marks it solved (once) only if the board is truly solved.
    @discardableResult
    func saveSudoku(_ game: SudokuGame, dayKey: String, challengeID: String?, now: Date) -> SudokuSave {
        let data = (try? JSONEncoder().encode(game)) ?? Data()
        let save: SudokuSave
        if let existing = sudokuSave(puzzleID: game.puzzleID) {
            save = existing
            // A solved game is final: never overwrite it with later edits.
            if existing.solvedAt != nil { return existing }
            existing.gameData = data
        } else {
            save = SudokuSave(puzzleID: game.puzzleID, gameData: data)
            context.insert(save)
        }
        if game.isSolved, save.solvedAt == nil {
            save.solvedAt = now
            save.solvedDayKey = dayKey
            save.challengeID = challengeID
        }
        save.needsSync = true
        save.updatedAt = Date()
        self.save()
        return save
    }

    // MARK: Facts for progress

    /// Every fact that can count toward a challenge.
    func facts() -> [ActivityFact] {
        var out = entries().map(\.fact)
        for s in sudokuSaves() {
            guard let at = s.solvedAt, let day = s.solvedDayKey, let cid = s.challengeID else { continue }
            out.append(ActivityFact(challengeID: cid, kind: "sudoku_solved", dayKey: day, amount: 1, ref: s.puzzleID, date: at))
        }
        return out
    }

    // MARK: Stamps

    func stamps() -> [StampRecord] { fetch(FetchDescriptor<StampRecord>(sortBy: [SortDescriptor(\.month)])) }

    func stamp(month: Int) -> StampRecord? { stamps().first { $0.month == month } }

    /// Records a completed month. Idempotent: a month can only ever have one stamp.
    @discardableResult
    func awardStamp(year: Int, month: Int, challengeID: String, completedAt: Date, verifiedAt: Date? = nil) -> (stamp: StampRecord, isNew: Bool) {
        if let existing = stamp(month: month) {
            if let verifiedAt, existing.verifiedAt == nil { existing.verifiedAt = verifiedAt; save() }
            return (existing, false)
        }
        let s = StampRecord(year: year, month: month, challengeID: challengeID, completedAt: completedAt)
        s.verifiedAt = verifiedAt
        context.insert(s)
        save()
        return (s, true)
    }

    // MARK: Discoveries

    func interactions() -> [CardInteraction] { fetch(FetchDescriptor<CardInteraction>()) }

    func interaction(cardID: String) -> CardInteraction? {
        fetch(FetchDescriptor<CardInteraction>(predicate: #Predicate { $0.cardID == cardID })).first
    }

    func interaction(cardID: String, dayKey: String, now: Date) -> CardInteraction {
        if let i = interaction(cardID: cardID) { return i }
        let i = CardInteraction(cardID: cardID, seenDayKey: dayKey, seenAt: now)
        context.insert(i)
        save()
        return i
    }

    func dayPick(_ dayKey: String) -> DayPick {
        if let p = fetch(FetchDescriptor<DayPick>(predicate: #Predicate { $0.dayKey == dayKey })).first { return p }
        let p = DayPick(dayKey: dayKey)
        context.insert(p)
        save()
        return p
    }

    func dayPicks() -> [DayPick] { fetch(FetchDescriptor<DayPick>(sortBy: [SortDescriptor(\.dayKey)])) }

    // MARK: Books

    func books() -> [Book] { fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.createdAt)])) }

    func addBook(title: String, author: String) -> Book {
        let b = Book(title: title, author: author)
        context.insert(b)
        save()
        return b
    }

    // MARK: Sync bookkeeping

    var hasUnsyncedChanges: Bool {
        entries(includeRemoved: true).contains { $0.needsSync }
            || sudokuSaves().contains { $0.needsSync }
            || interactions().contains { $0.needsSync }
    }

    /// Marks everything as needing upload (used when a guest signs in).
    func markAllForSync() {
        entries(includeRemoved: true).forEach { $0.needsSync = true }
        sudokuSaves().forEach { $0.needsSync = true; $0.serverVerified = false }
        interactions().forEach { $0.needsSync = true }
        save()
    }

    // MARK: Export and erase

    /// A complete, human-readable copy of everything stored on this device.
    func exportJSON(profile: ProfileRecord) -> Data {
        let iso = ISO8601DateFormatter()
        func d(_ date: Date?) -> Any { date.map { iso.string(from: $0) } ?? NSNull() }
        let root: [String: Any] = [
            "exportedAt": iso.string(from: Date()),
            "app": "TWELVE",
            "profile": [
                "displayName": profile.displayName, "timeZone": profile.timeZoneID, "joinedAt": d(profile.joinedAt),
                "feeling": profile.feelingRaw ?? NSNull(),
                "interests": profile.interests.map { ["category": $0.category, "subcategory": $0.subcategory ?? NSNull()] as [String: Any] },
            ] as [String: Any],
            "activity": entries().map { e in
                ["id": e.id.uuidString, "challenge": e.challengeID, "kind": e.kind, "day": e.dayKey, "date": d(e.date),
                 "amount": e.amount, "ref": e.ref ?? NSNull(), "title": e.title ?? NSNull(), "text": e.text ?? NSNull(),
                 "hasPhoto": e.photoFile != nil] as [String: Any]
            },
            "sudoku": sudokuSaves().map { s in
                ["puzzle": s.puzzleID, "solvedAt": d(s.solvedAt), "day": s.solvedDayKey ?? NSNull()] as [String: Any]
            },
            "stamps": stamps().map { s in
                ["year": s.year, "month": s.month, "completedAt": d(s.completedAt), "verifiedAt": d(s.verifiedAt),
                 "reflection": s.reflection ?? NSNull()] as [String: Any]
            },
            "discoveries": interactions().map { i in
                ["card": i.cardID, "seen": i.seenDayKey, "answered": i.answeredAt != nil, "saved": i.saved,
                 "dismissed": i.dismissed] as [String: Any]
            },
            "books": books().map { ["title": $0.title, "author": $0.author] },
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Erases every record and photo on this device.
    func eraseEverything() {
        for e in entries(includeRemoved: true) { context.delete(e) }
        for s in sudokuSaves() { context.delete(s) }
        for i in interactions() { context.delete(i) }
        for p in dayPicks() { context.delete(p) }
        for s in stamps() { context.delete(s) }
        for b in books() { context.delete(b) }
        for p in fetch(FetchDescriptor<ProfileRecord>()) { context.delete(p) }
        save()
        PhotoStore.deleteAll()
    }
}

enum Log {
    static func error(_ message: String) {
        #if DEBUG
        print("[TWELVE] \(message)")
        #endif
    }
}
