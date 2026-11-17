import XCTest
@testable import TwelveCore

final class ProgressTests: XCTestCase {
    let cal = YearCalendar(year: 2027, timeZone: TimeZone(identifier: "Europe/London")!)
    var catalog: ChallengeCatalog { .bundled }

    func fact(_ month: Int, _ day: Int, kind: String, amount: Double = 1, ref: String? = nil, hour: Int = 12) -> ActivityFact {
        ActivityFact(challengeID: ChallengeDefinition.id(year: 2027, month: month), kind: kind,
                     dayKey: cal.dayKey(month: month, day: day), amount: amount, ref: ref,
                     date: cal.date(month: month, day: day, hour: hour))
    }

    func testJanuaryNeedsSevenDistinctDays() {
        let jan = catalog.challenge(month: 1)!
        // Seven entries on one day count once.
        let sameDay = (0..<7).map { fact(1, 5, kind: "observation", hour: 8 + $0) }
        XCTAssertEqual(ProgressCalculator.progress(for: jan, facts: sameDay, calendar: cal).value, 1)
        let sixDays = (1...6).map { fact(1, $0, kind: "observation") }
        XCTAssertFalse(ProgressCalculator.progress(for: jan, facts: sixDays, calendar: cal).isComplete)
        let sevenDays = (1...7).map { fact(1, $0, kind: "observation") }
        let p = ProgressCalculator.progress(for: jan, facts: sevenDays, calendar: cal)
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.completedAt, cal.date(month: 1, day: 7, hour: 12))
    }

    func testActivityOutsideTheMonthDoesNotCount() {
        let jan = catalog.challenge(month: 1)!
        var facts = (1...6).map { fact(1, $0, kind: "observation") }
        // Tagged for January but dated 1 February: too late.
        facts.append(ActivityFact(challengeID: jan.id, kind: "observation", dayKey: "2027-02-01", date: cal.date(month: 2, day: 1)))
        XCTAssertFalse(ProgressCalculator.progress(for: jan, facts: facts, calendar: cal).isComplete)
    }

    func testFebruaryNeedsFiveDistinctSolvedPuzzles() {
        let feb = catalog.challenge(month: 2)!
        // The same puzzle solved five times counts once.
        let repeats = (1...5).map { fact(2, $0, kind: "sudoku_solved", ref: "m01") }
        let r = ProgressCalculator.progress(for: feb, facts: repeats, calendar: cal)
        XCTAssertEqual(r.value, 1)
        XCTAssertFalse(r.isComplete)
        let five = (1...5).map { fact(2, $0, kind: "sudoku_solved", ref: "m0\($0)") }
        XCTAssertTrue(ProgressCalculator.progress(for: feb, facts: five, calendar: cal).isComplete)
        // Opening a puzzle (no ref / other kind) never counts.
        let opened = (1...5).map { fact(2, $0, kind: "sudoku_opened", ref: "m0\($0)") }
        XCTAssertEqual(ProgressCalculator.progress(for: feb, facts: opened, calendar: cal).value, 0)
    }

    func testMarchThirtyMinutesAccumulate() {
        let mar = catalog.challenge(month: 3)!
        let sessions = (1...9).map { fact(3, $0, kind: "plank", amount: 200) } // 1800 s
        let p = ProgressCalculator.progress(for: mar, facts: sessions, calendar: cal)
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.value, 30, accuracy: 0.0001)
        let short = Array(sessions.dropLast())
        let q = ProgressCalculator.progress(for: mar, facts: short, calendar: cal)
        XCTAssertFalse(q.isComplete)
        XCTAssertEqual(q.value, 1600.0 / 60.0, accuracy: 0.0001)
    }

    func testImplausibleDurationsAreRejected() {
        let mar = catalog.challenge(month: 3)!
        let bad = [fact(3, 1, kind: "plank", amount: -50), fact(3, 2, kind: "plank", amount: 90_000),
                   fact(3, 3, kind: "plank", amount: .infinity), fact(3, 4, kind: "plank", amount: .nan)]
        XCTAssertEqual(ProgressCalculator.progress(for: mar, facts: bad, calendar: cal).value, 0)
        XCTAssertFalse(ProgressCalculator.isPlausible(kind: "reading", amount: 0))
        XCTAssertFalse(ProgressCalculator.isPlausible(kind: "reading", amount: 5000))
        XCTAssertTrue(ProgressCalculator.isPlausible(kind: "reading", amount: 20))
    }

    func testReadingPages() {
        let may = catalog.challenge(month: 5)!
        let logs = [fact(5, 2, kind: "reading", amount: 25), fact(5, 9, kind: "reading", amount: 35)]
        let p = ProgressCalculator.progress(for: may, facts: logs, calendar: cal)
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(ProgressCalculator.label(for: may, progress: p), "60 of 60 pages")
    }

    func testVocabularyNeedsRecallNotCardViews() {
        let jun = catalog.challenge(month: 6)!
        let words = (1...12).map { fact(6, 3, kind: "word_learned", ref: "es-\($0)") }
        let studied = ProgressCalculator.progress(for: jun, facts: words, calendar: cal)
        XCTAssertEqual(studied.value, 12)
        XCTAssertFalse(studied.isComplete, "viewing all cards is not completion")
        let passed = ProgressCalculator.progress(for: jun, facts: words + [fact(6, 4, kind: "quiz_pass")], calendar: cal)
        XCTAssertTrue(passed.isComplete)
        XCTAssertTrue(passed.quizPassed)
        // A pass without learning the words does not complete either.
        let passOnly = ProgressCalculator.progress(for: jun, facts: [fact(6, 4, kind: "quiz_pass")], calendar: cal)
        XCTAssertFalse(passOnly.isComplete)
        XCTAssertTrue(Vocabulary.passed(correct: 10, total: 12))
        XCTAssertFalse(Vocabulary.passed(correct: 9, total: 12))
    }

    func testFocusNeedsFullSessions() {
        let nov = catalog.challenge(month: 11)!
        let partial = (1...10).map { fact(11, $0, kind: "focus", amount: 599) }
        XCTAssertEqual(ProgressCalculator.progress(for: nov, facts: partial, calendar: cal).value, 0)
        let full = (1...10).map { fact(11, $0, kind: "focus", amount: 600) }
        XCTAssertTrue(ProgressCalculator.progress(for: nov, facts: full, calendar: cal).isComplete)
    }

    func testCreativeStagesAreDistinct() {
        let oct = catalog.challenge(month: 10)!
        let twice = [fact(10, 1, kind: "creative_stage", ref: "1"), fact(10, 2, kind: "creative_stage", ref: "1")]
        XCTAssertEqual(ProgressCalculator.progress(for: oct, facts: twice, calendar: cal).value, 1)
        let all = (1...3).map { fact(10, $0, kind: "creative_stage", ref: "\($0)") }
        XCTAssertTrue(ProgressCalculator.progress(for: oct, facts: all, calendar: cal).isComplete)
    }

    func testEveryChallengeCanBeCompleted() {
        // A sanity check that each catalog entry's metric and kind line up.
        for c in catalog.challenges {
            var facts: [ActivityFact] = []
            for day in 1...28 {
                for n in 0..<2 {
                    let amount: Double = c.metric == .sumMinutes ? 600 : (c.metric == .qualifyingSessions ? 600 : 5)
                    facts.append(fact(c.month, day, kind: c.entryKind, amount: amount, ref: "\(day)-\(n)", hour: 9 + n))
                }
            }
            facts.append(fact(c.month, 28, kind: ProgressCalculator.quizPassKind, hour: 20))
            XCTAssertTrue(ProgressCalculator.progress(for: c, facts: facts, calendar: cal).isComplete, "\(c.id) could not be completed")
            XCTAssertFalse(ProgressCalculator.progress(for: c, facts: [], calendar: cal).isComplete)
        }
    }

    func testClockFormatting() {
        XCTAssertEqual(ProgressCalculator.clock(444), "07:24")
        XCTAssertEqual(ProgressCalculator.clock(0), "00:00")
        XCTAssertEqual(ProgressCalculator.clock(3725), "1:02:05")
        XCTAssertEqual(ProgressCalculator.clock(-3), "00:00")
    }
}
