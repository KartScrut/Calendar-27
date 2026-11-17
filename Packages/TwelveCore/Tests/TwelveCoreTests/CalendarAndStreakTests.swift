import XCTest
@testable import TwelveCore

final class CalendarAndStreakTests: XCTestCase {
    let london = YearCalendar(year: 2027, timeZone: TimeZone(identifier: "Europe/London")!)
    let tokyo = YearCalendar(year: 2027, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    let la = YearCalendar(year: 2027, timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    func testPrelaunchBeforeTheYear() {
        let nov = YearCalendar(year: 2027, timeZone: TimeZone(identifier: "UTC")!)
        var c = DateComponents(); c.year = 2026; c.month = 12; c.day = 31; c.hour = 23
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: c)!
        XCTAssertEqual(nov.phase(at: date), .prelaunch(days: 1))
        XCTAssertNil(nov.currentMonth(at: date))
        XCTAssertFalse(nov.isRevealed(month: 1, at: date))
        XCTAssertEqual(nov.yearProgress(at: date), 0)
    }

    func testActiveAndEnded() {
        XCTAssertEqual(london.phase(at: london.date(month: 1, day: 1)), .active(month: 1, day: 1))
        XCTAssertEqual(london.phase(at: london.date(month: 11, day: 17, hour: 9)), .active(month: 11, day: 17))
        XCTAssertEqual(london.phase(at: london.yearEnd), .ended)
        XCTAssertEqual(london.daysInYear, 365)
        XCTAssertEqual(london.dayOfYear(at: london.date(month: 12, day: 31, hour: 12)), 365)
    }

    func testOnlyRevealedMonthsAreAvailable() {
        let now = london.date(month: 3, day: 10)
        let revealed = ChallengeCatalog.bundled.revealed(at: now, calendar: london).map(\.month)
        XCTAssertEqual(revealed, [1, 2, 3])
        XCTAssertEqual(london.currentMonth(at: now), 3)
        // One second before February: only January.
        let justBefore = london.revealDate(month: 2).addingTimeInterval(-1)
        XCTAssertEqual(ChallengeCatalog.bundled.revealed(at: justBefore, calendar: london).map(\.month), [1])
    }

    func testCatalogHasTwelveChallenges() {
        let all = ChallengeCatalog.bundled.challenges
        XCTAssertEqual(all.map(\.month), Array(1...12))
        XCTAssertEqual(Set(all.map(\.id)).count, 12)
        for c in all {
            XCTAssertGreaterThan(c.target, 0)
            XCTAssertFalse(c.instructions.isEmpty)
            XCTAssertFalse(c.story.isEmpty)
        }
        XCTAssertNotNil(ChallengeCatalog.bundled.challenge(month: 3)?.accessibleAlternative)
    }

    func testMonthLayout() {
        XCTAssertEqual(london.daysIn(month: 2), 28)
        XCTAssertEqual(london.daysIn(month: 12), 31)
        // 1 January 2027 is a Friday; 1 February 2027 is a Monday.
        XCTAssertEqual(london.leadingBlanks(month: 1), 4)
        XCTAssertEqual(london.leadingBlanks(month: 2), 0)
        XCTAssertEqual(london.weekdayIndex(for: london.date(month: 11, day: 17, hour: 12)), 2) // Wednesday
    }

    func testDayKeysAreStableAcrossTimeZoneChanges() {
        // 23:30 on 31 January in Los Angeles is already 1 February in Tokyo.
        let instant = la.date(month: 1, day: 31, hour: 23, minute: 30)
        XCTAssertEqual(la.dayKey(for: instant), "2027-01-31")
        XCTAssertEqual(tokyo.dayKey(for: instant), "2027-02-01")
        // The stored key decides the month — not where the phone is later.
        XCTAssertEqual(tokyo.month(ofDayKey: "2027-01-31"), 1)
        XCTAssertNil(london.month(ofDayKey: "2026-12-31"))
        XCTAssertNil(london.month(ofDayKey: "garbage"))
    }

    // MARK: Streaks

    func testJanuaryCompletionGivesOneMonth() {
        let s = StreakCalculator.summary(completed: [1], joinMonth: 1, currentMonth: 1, yearEnded: false)
        XCTAssertEqual(s.monthsCompleted, 1)
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertEqual(s.state(month: 1), .completed)
        XCTAssertEqual(s.state(month: 2), .sealed)
    }

    func testJanuaryAndFebruaryMakeStreakOfTwo() {
        let s = StreakCalculator.summary(completed: [1, 2], joinMonth: 1, currentMonth: 2, yearEnded: false)
        XCTAssertEqual(s.monthsCompleted, 2)
        XCTAssertEqual(s.currentStreak, 2)
    }

    func testOpenCurrentMonthDoesNotBreakStreak() {
        let s = StreakCalculator.summary(completed: [1, 2], joinMonth: 1, currentMonth: 3, yearEnded: false)
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertEqual(s.state(month: 3), .active)
    }

    func testMissingFebruaryBreaksStreakButKeepsTotal() {
        let march = StreakCalculator.summary(completed: [1], joinMonth: 1, currentMonth: 3, yearEnded: false)
        XCTAssertEqual(march.currentStreak, 0)
        XCTAssertEqual(march.monthsCompleted, 1)
        XCTAssertEqual(march.state(month: 2), .archived)
        let afterMarch = StreakCalculator.summary(completed: [1, 3], joinMonth: 1, currentMonth: 3, yearEnded: false)
        XCTAssertEqual(afterMarch.currentStreak, 1)
        XCTAssertEqual(afterMarch.monthsCompleted, 2)
        XCTAssertEqual(afterMarch.bestStreak, 1)
    }

    func testJoiningInJulyDoesNotCountEarlierMonthsAsMissed() {
        let s = StreakCalculator.summary(completed: [7, 8], joinMonth: 7, currentMonth: 9, yearEnded: false)
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertEqual(s.monthsCompleted, 2)
        for m in 1...6 { XCTAssertEqual(s.state(month: m), .beforeJoining) }
        XCTAssertFalse(s.states.contains(.archived))
    }

    func testDuplicateCompletionCannotDoubleCount() {
        // Completed months are a set: the same completion synced twice is one month.
        var completed = Set<Int>()
        completed.insert(1); completed.insert(1)
        let s = StreakCalculator.summary(completed: completed, joinMonth: 1, currentMonth: 1, yearEnded: false)
        XCTAssertEqual(s.monthsCompleted, 1)
        XCTAssertEqual(s.currentStreak, 1)
    }

    func testFullYear() {
        let s = StreakCalculator.summary(completed: Set(1...12), joinMonth: 1, currentMonth: nil, yearEnded: true)
        XCTAssertEqual(s.monthsCompleted, 12)
        XCTAssertEqual(s.currentStreak, 12)
        XCTAssertEqual(s.bestStreak, 12)
    }

    func testNothingCountsBeforeTheYear() {
        let s = StreakCalculator.summary(completed: [], joinMonth: 1, currentMonth: nil, yearEnded: false)
        XCTAssertEqual(s.monthsCompleted, 0)
        XCTAssertEqual(s.states, Array(repeating: .sealed, count: 12))
    }

    func testJoinMonth() {
        XCTAssertEqual(StreakCalculator.joinMonth(joinDate: london.date(month: 7, day: 14), calendar: london), 7)
        XCTAssertEqual(StreakCalculator.joinMonth(joinDate: london.yearStart.addingTimeInterval(-86_400 * 40), calendar: london), 1)
    }

    func testEditorialOverridesCannotChangeStartedCriteria() {
        let now = london.date(month: 2, day: 10)
        let feb = ChallengeCatalog.bundled.challenge(month: 2)!
        let data = try! JSONEncoder().encode(feb)
        var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["target"] = 1.0
        json["version"] = 2
        let tampered = try! JSONDecoder().decode(ChallengeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        let merged = ChallengeCatalog.bundled.applying(overrides: [tampered], at: now, calendar: london)
        XCTAssertEqual(merged.challenge(month: 2)?.target, 5)
        // Copy-only edits to a started month are allowed.
        json["target"] = 5.0
        json["story"] = "New copy"
        let copyEdit = try! JSONDecoder().decode(ChallengeDefinition.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(ChallengeCatalog.bundled.applying(overrides: [copyEdit], at: now, calendar: london).challenge(month: 2)?.story, "New copy")
    }

    func testDeepLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "twelve://spark")!), .spark)
        XCTAssertEqual(DeepLink(url: DeepLink.challenge.url), .challenge)
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/spark")!))
        XCTAssertEqual(DeepLink(shortcutType: "com.twelve.app.year"), .year)
    }
}
