import XCTest
@testable import TwelveCore

final class DiscoveryAndWidgetTests: XCTestCase {
    func testLibraryMeetsEditorialRequirements() {
        let cards = DiscoveryLibrary.cards
        for category in Interests.all {
            let n = cards.filter { $0.category == category.id }.count
            XCTAssertGreaterThanOrEqual(n, 20, "\(category.name) needs at least 20 cards")
        }
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
        for c in cards {
            XCTAssertTrue((50...120).contains(c.wordCount), "\(c.id) has \(c.wordCount) words")
            XCTAssertTrue(c.sourceURL.hasPrefix("https://"), c.id)
            XCTAssertNotNil(URL(string: c.sourceURL), c.id)
            XCTAssertFalse(c.headline.isEmpty)
            XCTAssertTrue(c.quiz != nil || c.prompt != nil, "\(c.id) needs an interaction")
            if let q = c.quiz { XCTAssertTrue(q.options.indices.contains(q.answer), c.id) }
            XCTAssertNotNil(Interests.category(c.category), c.id)
        }
        XCTAssertGreaterThanOrEqual(DiscoveryLibrary.micro.count, 30)
    }

    func testSparkIsStableForADayAndPersonal() {
        let interests = [InterestChoice(category: "design"), InterestChoice(category: "nature")]
        let a = SparkSelector.pick(dayKey: "2027-01-05", seed: "u1", interests: interests, seen: [], dismissed: [], lastCategory: nil)
        let b = SparkSelector.pick(dayKey: "2027-01-05", seed: "u1", interests: interests, seen: [], dismissed: [], lastCategory: nil)
        XCTAssertEqual(a, b)
        var categories = Set<String>()
        for day in 1...28 {
            let key = YearCalendar.key(year: 2027, month: 1, day: day)
            let card = SparkSelector.pick(dayKey: key, seed: "u1", interests: interests, seen: [], dismissed: [], lastCategory: nil)!
            categories.insert(card.category)
        }
        XCTAssertTrue(categories.isSubset(of: ["design", "nature"]))
        XCTAssertEqual(categories.count, 2, "both interests should appear over a month")
    }

    func testSparkAvoidsSeenAndDismissedCards() {
        let interests = [InterestChoice(category: "science"), InterestChoice(category: "history")]
        var seen = Set<String>()
        var last: String?
        var picks: [String] = []
        for day in 0..<40 {
            let card = SparkSelector.pick(dayKey: "day-\(day)", seed: "u", interests: interests, seen: seen, dismissed: [], lastCategory: last)!
            XCTAssertFalse(seen.contains(card.id), "repeated a card while fresh ones remained")
            seen.insert(card.id); last = card.category; picks.append(card.id)
        }
        XCTAssertEqual(Set(picks).count, 40)
        let dismissed = Set(DiscoveryLibrary.cards.filter { $0.category == "science" }.map(\.id))
        for day in 0..<20 {
            let card = SparkSelector.pick(dayKey: "d\(day)", seed: "u", interests: [InterestChoice(category: "science")], seen: [], dismissed: dismissed, lastCategory: nil)!
            XCTAssertFalse(dismissed.contains(card.id))
            XCTAssertEqual(card.evergreen, true, "falls back to a verified evergreen card")
        }
    }

    func testSubcategoryPreferenceShiftsSelection() {
        let f1 = [InterestChoice(category: "sports", subcategory: "f1")]
        var hits = 0
        for day in 0..<60 {
            let card = SparkSelector.pick(dayKey: "x\(day)", seed: "s", interests: f1, seen: [], dismissed: [], lastCategory: nil)!
            if card.subcategory == "f1" { hits += 1 }
        }
        XCTAssertGreaterThan(hits, 20, "a chosen subcategory should be favoured (5 of 20 cards = 15 by chance)")
    }

    func testSparkAlwaysReturnsSomethingEvenWhenEverythingIsSeen() {
        let all = Set(DiscoveryLibrary.cards.map(\.id))
        XCTAssertNotNil(SparkSelector.pick(dayKey: "z", seed: "s", interests: [InterestChoice(category: "books")], seen: all, dismissed: [], lastCategory: nil))
        XCTAssertNil(SparkSelector.pick(dayKey: "z", seed: "s", interests: [], seen: [], dismissed: [], lastCategory: nil, library: []))
    }

    func testMicroChallengeSelection() {
        let m = SparkSelector.pickMicro(dayKey: "2027-02-02", seed: "u", interests: [InterestChoice(category: "art")], feeling: .creative, recent: [], avoidCategory: nil)
        XCTAssertNotNil(m)
        XCTAssertEqual(m, SparkSelector.pickMicro(dayKey: "2027-02-02", seed: "u", interests: [InterestChoice(category: "art")], feeling: .creative, recent: [], avoidCategory: nil))
        for mc in DiscoveryLibrary.micro { XCTAssertTrue((1...5).contains(mc.minutes), mc.id) }
    }

    func testVocabularyContent() {
        XCTAssertGreaterThanOrEqual(Vocabulary.languages.count, 3)
        for lang in Vocabulary.languages {
            XCTAssertEqual(lang.words.count, Vocabulary.wordsToLearn, lang.id)
            XCTAssertEqual(Set(lang.words.map(\.word)).count, lang.words.count)
            let quiz = Vocabulary.quiz(words: lang.words, seed: "a")
            XCTAssertEqual(quiz.count, 12)
            for q in quiz {
                XCTAssertEqual(q.options.count, 4)
                XCTAssertEqual(Set(q.options).count, 4)
                let word = lang.words.first { $0.id == q.id }!
                XCTAssertEqual(q.options[q.answer], word.word)
            }
        }
    }

    // MARK: Widgets

    func testWidgetSnapshotCountsAndLabels() {
        var snap = WidgetSnapshot()
        XCTAssertEqual(snap.countLabel, "00 / 12")
        snap.completedMonths = [1]
        XCTAssertEqual(snap.completeLabel, "1 month complete")
        XCTAssertEqual(snap.countLabel, "01 / 12")
        snap.completedMonths = [1, 2, 2] // a duplicate must not inflate the count
        XCTAssertEqual(snap.completedCount, 2)
        XCTAssertEqual(snap.completeLabel, "2 months complete")
    }

    func testWidgetSnapshotRoundTripsAndDefaultsWhenMissing() {
        let suite = "widget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Signed-out / fresh install: an empty, valid snapshot.
        XCTAssertEqual(WidgetSnapshot.load(from: defaults).completedCount, 0)
        XCTAssertFalse(WidgetSnapshot.load(from: defaults).onboarded)
        let snap = WidgetSnapshot.preview
        snap.save(to: defaults)
        XCTAssertEqual(WidgetSnapshot.load(from: defaults), snap)
        defaults.removePersistentDomain(forName: suite)
    }

    func testWidgetNeverShowsAStaleMonthsChallenge() {
        let tz = TimeZone(identifier: "UTC")!
        let cal = YearCalendar(year: 2027, timeZone: tz)
        var snap = WidgetSnapshot(timeZoneID: "UTC", challengeMonth: 3, challengeTitle: "Build your core")
        XCTAssertTrue(snap.challengeIsCurrent(at: cal.date(month: 3, day: 20)))
        XCTAssertFalse(snap.challengeIsCurrent(at: cal.date(month: 4, day: 1)), "April must not show March's card")
        snap.challengeMonth = nil
        XCTAssertFalse(snap.challengeIsCurrent(at: cal.date(month: 3, day: 20)))
    }

    func testSeededGeneratorIsDeterministic() {
        var a = SeededGenerator(string: "hello"), b = SeededGenerator(string: "hello"), c = SeededGenerator(string: "world")
        let x = a.next(), y = b.next(), z = c.next()
        XCTAssertEqual(x, y)
        XCTAssertNotEqual(x, z)
    }
}
