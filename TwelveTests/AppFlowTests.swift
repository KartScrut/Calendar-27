import SwiftData
import TwelveCore
import XCTest
@testable import Twelve

/// End-to-end behaviour of the app model against an in-memory database,
/// with the clock moved to chosen dates in 2027.
@MainActor
final class AppFlowTests: XCTestCase {
    private let calendar = YearCalendar(year: 2027, timeZone: .current)

    override func setUp() async throws {
        TimerStore.save(nil)
        MicroInbox.clear()
    }

    override func tearDown() async throws {
        AppClock.simulate(nil)
        TimerStore.save(nil)
    }

    private func at(_ month: Int, _ day: Int, hour: Int = 10, minute: Int = 0) {
        AppClock.simulate(calendar.date(month: month, day: day, hour: hour, minute: minute))
    }

    private func makeApp(onboarded: Bool = true) -> AppModel {
        let app = AppModel(inMemory: true, auth: AuthService(config: nil))
        if onboarded {
            app.updateProfile { $0.interests = [InterestChoice(category: "design"), InterestChoice(category: "science")] }
            app.finishOnboarding()
        }
        return app
    }

    // MARK: Before the year

    func testNothingCanBeEarnedBeforeTheYearBegins() throws {
        AppClock.simulate(calendar.yearStart.addingTimeInterval(-40 * 86_400))
        let app = makeApp()
        guard case .prelaunch = app.phase else { return XCTFail("expected prelaunch") }
        XCTAssertNil(app.currentChallenge)
        XCTAssertNil(app.revealedChallenge(month: 1), "January must stay sealed")
        let january = try XCTUnwrap(ChallengeCatalog.bundled.challenge(month: 1))
        XCTAssertNil(app.log(january, text: "early"))
        XCTAssertTrue(app.store.entries().isEmpty)
        XCTAssertEqual(app.summary.monthsCompleted, 0)
        XCTAssertNil(app.spark, "daily picks wait for the year too")
    }

    // MARK: Reveal rules

    func testOnlyTheCurrentAndPastMonthsAreRevealed() {
        at(2, 10)
        let app = makeApp()
        XCTAssertEqual(app.currentChallenge?.month, 2)
        XCTAssertNotNil(app.revealedChallenge(month: 1))
        XCTAssertNotNil(app.revealedChallenge(month: 2))
        for month in 3...12 { XCTAssertNil(app.revealedChallenge(month: month), "month \(month) must be sealed") }
        XCTAssertEqual(app.summary.state(month: 3), .sealed)
    }

    func testOnlyTheOpenMonthAcceptsActivity() throws {
        at(2, 10)
        let app = makeApp()
        let january = try XCTUnwrap(app.revealedChallenge(month: 1))
        let march = try XCTUnwrap(ChallengeCatalog.bundled.challenge(month: 3))
        XCTAssertNil(app.log(january, text: "late"))
        XCTAssertNil(app.log(march, amount: 60))
        XCTAssertTrue(app.store.entries().isEmpty)
    }

    // MARK: Completion and streaks

    private func completeJanuary(_ app: AppModel) throws {
        let january = try XCTUnwrap(ChallengeCatalog.bundled.challenge(month: 1))
        for day in 2...8 {
            at(1, day)
            app.refresh()
            XCTAssertNotNil(app.log(january, text: "Noticed something on day \(day)"))
        }
    }

    func testCompletingJanuaryAwardsExactlyOneStamp() throws {
        at(1, 2)
        let app = makeApp()
        try completeJanuary(app)
        XCTAssertEqual(app.summary.monthsCompleted, 1)
        XCTAssertEqual(app.summary.currentStreak, 1)
        XCTAssertEqual(app.celebration?.month, 1, "completion triggers the celebration")
        // Recomputing, or the same completion arriving again, changes nothing.
        app.refresh(); app.refresh()
        let again = app.store.awardStamp(year: 2027, month: 1, challengeID: "2027-01", completedAt: Date())
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(app.store.stamps().count, 1)
        XCTAssertEqual(app.summary.monthsCompleted, 1)
    }

    func testSixDaysIsNotEnoughAndSameDayCountsOnce() throws {
        at(1, 5)
        let app = makeApp()
        let january = try XCTUnwrap(app.currentChallenge)
        for _ in 0..<9 { app.log(january, text: "again") }
        XCTAssertEqual(app.progress(for: january).value, 1)
        XCTAssertEqual(app.summary.monthsCompleted, 0)
    }

    func testAStampSurvivesDeletingAnEntry() throws {
        at(1, 2)
        let app = makeApp()
        try completeJanuary(app)
        let entry = try XCTUnwrap(app.store.entries().first)
        app.remove(entry)
        XCTAssertEqual(app.summary.monthsCompleted, 1, "an achievement is never taken away")
    }

    func testStreakAcrossMonthsAndAMissedMonth() throws {
        at(1, 2)
        let app = makeApp()
        try completeJanuary(app)
        // February passes untouched; in March the streak has ended, the total has not.
        at(3, 5)
        app.refresh()
        XCTAssertEqual(app.summary.monthsCompleted, 1)
        XCTAssertEqual(app.summary.currentStreak, 0)
        XCTAssertEqual(app.summary.state(month: 2), .archived)
        XCTAssertEqual(app.summary.state(month: 1), .completed)
    }

    func testJoiningInJulyDoesNotMarkEarlierMonthsAsMissed() {
        at(7, 14)
        let app = makeApp()
        for month in 1...6 { XCTAssertEqual(app.summary.state(month: month), .beforeJoining) }
        XCTAssertEqual(app.summary.state(month: 7), .active)
    }

    // MARK: Sudoku

    private func solved(_ puzzle: SudokuPuzzle) throws -> SudokuGame {
        let solution = try XCTUnwrap(SudokuSolver.solve(puzzle.cells))
        var game = SudokuGame(puzzle: puzzle)
        for i in 0..<81 where !game.isGiven(i) { game.place(solution[i], at: i) }
        return game
    }

    func testFiveDistinctSolvedBoardsCompleteFebruary() throws {
        at(2, 3)
        let app = makeApp()
        let february = try XCTUnwrap(app.currentChallenge)
        let puzzles = Array(SudokuLibrary.all.prefix(5))

        // Opening a puzzle, or saving an unfinished or incorrect board, counts for nothing.
        app.saveSudoku(SudokuGame(puzzle: puzzles[0]))
        var wrong = try solved(puzzles[0])
        let cell = try XCTUnwrap((0..<81).first { !wrong.isGiven($0) })
        wrong.place(wrong.values[cell] % 9 + 1, at: cell)
        app.saveSudoku(wrong)
        XCTAssertEqual(app.progress(for: february).value, 0)

        // The same board solved repeatedly counts once.
        let first = try solved(puzzles[0])
        app.saveSudoku(first); app.saveSudoku(first); app.saveSudoku(first)
        XCTAssertEqual(app.progress(for: february).value, 1)

        for p in puzzles.dropFirst() { app.saveSudoku(try solved(p)) }
        XCTAssertEqual(app.progress(for: february).value, 5)
        XCTAssertEqual(app.summary.state(month: 2), .completed)
    }

    func testSavedGameResumesExactly() throws {
        at(2, 3)
        let app = makeApp()
        var game = SudokuGame(puzzle: SudokuLibrary.all[3])
        let empties = (0..<81).filter { !game.isGiven($0) }
        game.place(5, at: empties[0])
        game.toggleNote(2, at: empties[1])
        app.saveSudoku(game)
        XCTAssertEqual(app.store.sudokuSave(puzzleID: game.puzzleID)?.game, game)
    }

    // MARK: Timers

    func testTimerExcludesPausedTimeAndLogsOnce() throws {
        at(3, 4, hour: 7)
        let app = makeApp()
        let march = try XCTUnwrap(app.currentChallenge)
        let start = calendar.date(month: 3, day: 4, hour: 7)
        app.timer.start(march, kind: .plank, variant: nil)
        XCTAssertNotNil(app.timer.session)

        AppClock.simulate(start.addingTimeInterval(100)); app.timer.pause()
        AppClock.simulate(start.addingTimeInterval(500)); app.timer.resume()
        // "Relaunch": a fresh controller reads the same stored session.
        let relaunched = TimerController()
        XCTAssertEqual(relaunched.session?.id, app.timer.session?.id)
        AppClock.simulate(start.addingTimeInterval(530))
        let logged = try XCTUnwrap(app.timer.finish())
        XCTAssertEqual(logged, 130, accuracy: 2)
        XCTAssertNil(app.timer.finish(), "finishing twice logs once")
        XCTAssertEqual(app.store.entries().count, 1)
        XCTAssertNil(TimerStore.load())
        XCTAssertEqual(app.progress(for: march).value, 130.0 / 60.0, accuracy: 0.05)
    }

    func testThirtyMinutesOfSessionsCompleteMarch() throws {
        at(3, 4)
        let app = makeApp()
        let march = try XCTUnwrap(app.currentChallenge)
        for _ in 0..<5 { XCTAssertNotNil(app.log(march, amount: 300)) }
        XCTAssertEqual(app.summary.monthsCompleted, 0)
        XCTAssertNotNil(app.log(march, amount: 300))
        XCTAssertEqual(app.summary.state(month: 3), .completed)
        XCTAssertNil(app.log(march, amount: -10), "negative durations are rejected")
        XCTAssertNil(app.log(march, amount: 90_000), "implausible durations are rejected")
    }

    func testASessionStartedBeforeMidnightBelongsToItsOwnMonth() throws {
        at(3, 31, hour: 23, minute: 58)
        let app = makeApp()
        let march = try XCTUnwrap(app.currentChallenge)
        app.timer.start(march, kind: .plank, variant: nil)
        AppClock.simulate(calendar.date(month: 4, day: 1, hour: 0, minute: 1))
        app.refresh()
        XCTAssertNotNil(app.timer.finish())
        XCTAssertEqual(app.store.entries().first?.dayKey, "2027-03-31")
    }

    // MARK: Discoveries

    func testSparkIsPersonalStableAndCannotBeFarmed() throws {
        at(5, 6)
        let app = makeApp()
        let card = try XCTUnwrap(app.spark)
        XCTAssertTrue(["design", "science"].contains(card.category))
        app.refresh()
        XCTAssertEqual(app.spark?.id, card.id, "the day's Spark doesn't change on refresh")
        _ = app.answer(card, option: 0)
        _ = app.answer(card, option: 1)
        _ = app.answer(card, option: 2)
        XCTAssertEqual(app.points, Points.sparkInteraction, "answering again earns nothing more")
        app.completeMicro(); app.completeMicro()
        XCTAssertEqual(app.points, Points.sparkInteraction + Points.microChallenge)
        // Not interested: the card is replaced and never returns.
        app.dismiss(card)
        XCTAssertNotEqual(app.spark?.id, card.id)
        XCTAssertEqual(app.summary.monthsCompleted, 0, "discovery points never touch the monthly streak")
    }

    // MARK: Persistence, export, erase

    func testProgressSurvivesReopeningTheDatabase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("twelve-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = Schema(Persistence.models)
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let store = DataStore(container: container)
            store.add(ActivityEntry(challengeID: "2027-05", kind: "reading", dayKey: "2027-05-03", date: Date(), amount: 25))
            store.awardStamp(year: 2027, month: 1, challengeID: "2027-01", completedAt: Date())
        }
        let reopened = DataStore(container: try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]))
        XCTAssertEqual(reopened.entries().count, 1)
        XCTAssertEqual(reopened.entries().first?.amount, 25)
        XCTAssertEqual(reopened.stamps().map(\.month), [1])
    }

    func testExportAndErase() throws {
        at(7, 2)
        let app = makeApp()
        let july = try XCTUnwrap(app.currentChallenge)
        app.log(july, text: "Helped a neighbour carry shopping")
        let data = app.store.exportJSON(profile: app.profile)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("Helped a neighbour carry shopping"))
        app.eraseDevice()
        XCTAssertTrue(app.store.entries().isEmpty)
        XCTAssertFalse(app.isOnboarded)
    }

    func testGuestProgressIsQueuedForUploadNotOverwritten() throws {
        at(7, 2)
        let app = makeApp()
        let july = try XCTUnwrap(app.currentChallenge)
        let entry = try XCTUnwrap(app.log(july, text: "One"))
        entry.needsSync = false
        app.store.markAllForSync()
        XCTAssertTrue(app.store.hasUnsyncedChanges)
        XCTAssertEqual(app.store.entries().count, 1, "marking for sync never removes local work")
    }

    // MARK: Navigation

    func testDeepLinksOpenTheRightPlace() {
        at(3, 4)
        let app = makeApp()
        app.open(.year)
        XCTAssertEqual(app.tab, .calendar)
        XCTAssertTrue(app.showYearOverview)
        app.open(.challenge)
        XCTAssertEqual(app.sheet, .challenge(month: 3))
        app.open(.spark)
        XCTAssertEqual(app.sheet, .spark)
        app.open(.today)
        XCTAssertNil(app.sheet)
        XCTAssertEqual(app.tab, .today)
        // Before onboarding, links do nothing.
        let fresh = makeApp(onboarded: false)
        fresh.open(.challenge)
        XCTAssertNil(fresh.sheet)
    }

    // MARK: Notifications

    func testReminderWordingUsesRealProgress() throws {
        let february = try XCTUnwrap(ChallengeCatalog.bundled.challenge(month: 2))
        let three = ChallengeProgress(value: 3, target: 5, isComplete: false, completedAt: nil, quizPassed: false)
        XCTAssertEqual(NotificationService.progressLine(challenge: february, progress: three), "3 puzzles down. 2 to go.")

        var reminders = ReminderPreferences()
        let now = calendar.date(month: 2, day: 10)
        XCTAssertTrue(NotificationService.plan(reminders: reminders, calendar: calendar, now: now, challenge: february,
                                               progress: three, completed: false).isEmpty, "nothing is scheduled unless chosen")
        reminders.progress = true
        reminders.monthlyReveal = true
        reminders.dailySpark = true
        let plan = NotificationService.plan(reminders: reminders, calendar: calendar, now: now, challenge: february,
                                            progress: three, completed: false)
        XCTAssertEqual(plan.filter { $0.id.contains("reveal") }.count, 10, "one announcement for each month still ahead")
        XCTAssertEqual(plan.first { $0.id.hasSuffix("progress") }?.body, "3 puzzles down. 2 to go.")
        XCTAssertFalse(plan.contains { $0.body.contains("Build your core") }, "announcements never name a sealed challenge")
        let done = NotificationService.plan(reminders: reminders, calendar: calendar, now: now, challenge: february,
                                            progress: three, completed: true)
        XCTAssertNil(done.first { $0.id.hasSuffix("progress") }, "no progress nudge once the month is complete")
    }

    // MARK: Backend helpers

    func testServerDatesParse() throws {
        let micro = try XCTUnwrap(ServerDate.parse("2027-01-05T09:30:00.123456+00:00"))
        let plain = try XCTUnwrap(ServerDate.parse("2027-01-05T09:30:00+00:00"))
        XCTAssertEqual(micro.timeIntervalSince(plain), 0.123, accuracy: 0.001)
        XCTAssertNil(ServerDate.parse("not a date"))
        XCTAssertNotNil(ServerDate.parse(ServerDate.string(Date())))
    }

    func testBackendIsOptionalAndEmailIsValidated() {
        let auth = AuthService(config: nil)
        XCTAssertEqual(auth.state, .unavailable)
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertTrue(AuthService.isPlausibleEmail("someone@example.com"))
        XCTAssertFalse(AuthService.isPlausibleEmail("someone@"))
        XCTAssertFalse(AuthService.isPlausibleEmail("no at sign"))
        XCTAssertFalse(AuthService.isPlausibleEmail("@example.com"))
    }
}
