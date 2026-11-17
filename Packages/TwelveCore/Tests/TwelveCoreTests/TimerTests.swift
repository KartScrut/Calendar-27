import XCTest
@testable import TwelveCore

final class TimerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testPausedTimeIsExcluded() {
        var s = TimerSession(challengeID: "2027-03", kind: .plank, startedAt: t0)
        XCTAssertTrue(s.pause(at: t0.addingTimeInterval(60)))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(500)), 60, accuracy: 0.001)
        XCTAssertTrue(s.resume(at: t0.addingTimeInterval(500)))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(530)), 90, accuracy: 0.001)
        XCTAssertTrue(s.finish(at: t0.addingTimeInterval(540)))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(9_999)), 100, accuracy: 0.001)
        XCTAssertEqual(s.loggableSeconds(at: t0.addingTimeInterval(9_999)), 100)
    }

    func testBackgroundingDoesNotResetASession() {
        // Nothing ticks in the background: elapsed time comes from timestamps.
        let s = TimerSession(challengeID: "2027-09", kind: .walk, startedAt: t0)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(1_234)), 1_234, accuracy: 0.001)
        XCTAssertTrue(s.isRunning)
    }

    func testTerminationAndRestartKeepDuration() throws {
        var s = TimerSession(challengeID: "2027-03", kind: .plank, startedAt: t0)
        s.pause(at: t0.addingTimeInterval(45))
        let suite = "timer-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        TimerStore.save(s, to: defaults)
        // "Relaunch": read it back from storage.
        var restored = try XCTUnwrap(TimerStore.load(from: defaults))
        XCTAssertEqual(restored, s)
        restored.resume(at: t0.addingTimeInterval(3_600))
        XCTAssertEqual(restored.elapsed(at: t0.addingTimeInterval(3_615)), 60, accuracy: 0.001)
        TimerStore.save(nil, to: defaults)
        XCTAssertNil(TimerStore.load(from: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    func testSessionsAreClampedToTheirCeiling() {
        let forgotten = TimerSession(challengeID: "2027-03", kind: .plank, startedAt: t0)
        let later = t0.addingTimeInterval(86_400)
        XCTAssertEqual(forgotten.elapsed(at: later), TimerKind.plank.maximumSeconds)
        XCTAssertTrue(forgotten.reachedLimit(at: later))
        XCTAssertEqual(forgotten.loggableSeconds(at: later), TimerKind.plank.maximumSeconds)
    }

    func testClockGoingBackwardsNeverGivesNegativeTime() {
        var s = TimerSession(challengeID: "2027-03", kind: .plank, startedAt: t0)
        s.pause(at: t0.addingTimeInterval(-500)) // clock was changed
        XCTAssertGreaterThanOrEqual(s.elapsed(at: t0), 0)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(-9_000)), 0, accuracy: 0.001)
        XCTAssertNil(s.loggableSeconds(at: t0), "a zero-length session is not logged")
    }

    func testInvalidTransitionsAreIgnored() {
        var s = TimerSession(challengeID: "2027-03", kind: .plank, startedAt: t0)
        XCTAssertFalse(s.resume(at: t0.addingTimeInterval(1)))
        XCTAssertTrue(s.pause(at: t0.addingTimeInterval(10)))
        XCTAssertFalse(s.pause(at: t0.addingTimeInterval(20)))
        XCTAssertTrue(s.finish(at: t0.addingTimeInterval(30)))
        XCTAssertFalse(s.finish(at: t0.addingTimeInterval(40)))
        XCTAssertFalse(s.resume(at: t0.addingTimeInterval(50)))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(60)), 10, accuracy: 0.001)
    }

    func testFocusSessionOnlyCountsWhenFull() {
        let s = TimerSession(challengeID: "2027-11", kind: .focus, startedAt: t0)
        XCTAssertNil(s.loggableSeconds(at: t0.addingTimeInterval(599)))
        XCTAssertEqual(s.loggableSeconds(at: t0.addingTimeInterval(600)), 600)
        XCTAssertEqual(s.loggableSeconds(at: t0.addingTimeInterval(5_000)), 600)
        XCTAssertEqual(s.projectedDate(reaching: 600, from: t0.addingTimeInterval(100)), t0.addingTimeInterval(600))
    }

    func testMultipleSessionsAccumulateToThirtyMinutes() {
        let cal = YearCalendar(year: 2027, timeZone: TimeZone(identifier: "UTC")!)
        let march = ChallengeCatalog.bundled.challenge(month: 3)!
        var facts: [ActivityFact] = []
        for day in 1...6 {
            let start = cal.date(month: 3, day: day, hour: 7)
            var s = TimerSession(challengeID: march.id, kind: .plank, startedAt: start)
            s.pause(at: start.addingTimeInterval(150))
            s.resume(at: start.addingTimeInterval(400))
            s.finish(at: start.addingTimeInterval(550))
            let seconds = s.loggableSeconds(at: start.addingTimeInterval(600))!
            XCTAssertEqual(seconds, 300)
            facts.append(ActivityFact(challengeID: march.id, kind: "plank", dayKey: cal.dayKey(for: start), amount: seconds, date: start))
        }
        XCTAssertTrue(ProgressCalculator.progress(for: march, facts: facts, calendar: cal).isComplete)
        XCTAssertFalse(ProgressCalculator.progress(for: march, facts: Array(facts.dropLast()), calendar: cal).isComplete)
    }
}
