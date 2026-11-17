import XCTest
@testable import TwelveCore

final class SudokuTests: XCTestCase {
    func testLibraryIsLargeEnough() {
        XCTAssertGreaterThanOrEqual(SudokuLibrary.all.filter { $0.difficulty == .medium }.count, 10)
        XCTAssertGreaterThanOrEqual(SudokuLibrary.all.filter { $0.difficulty == .hard }.count, 10)
        XCTAssertEqual(Set(SudokuLibrary.all.map(\.id)).count, SudokuLibrary.all.count)
        XCTAssertEqual(Set(SudokuLibrary.all.map(\.givens)).count, SudokuLibrary.all.count)
    }

    func testEveryPuzzleHasExactlyOneSolution() {
        for p in SudokuLibrary.all {
            XCTAssertEqual(p.cells.count, 81, p.id)
            XCTAssertEqual(SudokuSolver.countSolutions(p.cells, limit: 2), 1, "\(p.id) must have a unique solution")
            let solution = SudokuSolver.solve(p.cells)
            XCTAssertNotNil(solution, p.id)
            XCTAssertFalse(solution!.contains(0))
            XCTAssertTrue(SudokuSolver.isConsistent(solution!))
        }
    }

    func testSolverDetectsMultipleAndNoSolutions() {
        XCTAssertEqual(SudokuSolver.countSolutions(Array(repeating: 0, count: 81), limit: 2), 2)
        var broken = Array(repeating: 0, count: 81)
        broken[0] = 5; broken[1] = 5
        XCTAssertEqual(SudokuSolver.countSolutions(broken), 0)
        XCTAssertNil(SudokuSolver.solve(broken))
    }

    func testIncorrectBoardIsNeverSolved() {
        let p = SudokuLibrary.all[0]
        let solution = SudokuSolver.solve(p.cells)!
        var game = SudokuGame(puzzle: p)
        XCTAssertFalse(game.isSolved)
        for i in 0..<81 where !game.isGiven(i) { game.place(solution[i], at: i) }
        XCTAssertTrue(game.isSolved)
        // Swap in a wrong digit: full board, but not solved.
        let i = (0..<81).first { !game.isGiven($0) }!
        let wrong = solution[i] % 9 + 1
        game.place(wrong, at: i)
        XCTAssertEqual(game.filledCount, 81)
        XCTAssertFalse(game.isSolved)
        XCTAssertFalse(game.conflicts.isEmpty)
    }

    func testGivensCannotBeChanged() {
        let p = SudokuLibrary.all[0]
        var game = SudokuGame(puzzle: p)
        let given = (0..<81).first { game.isGiven($0) }!
        let before = game.values[given]
        game.place(before % 9 + 1, at: given)
        game.erase(at: given)
        game.toggleNote(3, at: given)
        XCTAssertEqual(game.values[given], before)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoRedoAndNotes() {
        var game = SudokuGame(puzzle: SudokuLibrary.all[1])
        let i = (0..<81).first { !game.isGiven($0) }!
        game.toggleNote(4, at: i)
        game.toggleNote(7, at: i)
        XCTAssertTrue(game.hasNote(4, at: i) && game.hasNote(7, at: i))
        game.place(4, at: i)
        XCTAssertEqual(game.values[i], 4)
        XCTAssertFalse(game.hasNote(7, at: i), "placing a digit clears the pencil marks")
        game.undo()
        XCTAssertEqual(game.values[i], 0)
        XCTAssertTrue(game.hasNote(7, at: i), "undo restores the pencil marks")
        game.redo()
        XCTAssertEqual(game.values[i], 4)
        game.erase(at: i)
        XCTAssertEqual(game.values[i], 0)
        game.undo(); game.undo(); game.undo(); game.undo()
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(game.notes[i], 0)
    }

    func testSavedGameRestoresExactly() throws {
        var game = SudokuGame(puzzle: SudokuLibrary.all[2])
        let empties = (0..<81).filter { !game.isGiven($0) }
        game.place(3, at: empties[0])
        game.toggleNote(5, at: empties[1])
        game.elapsedSeconds = 321
        if let hint = game.nextHint() { game.applyHint(hint) }
        let data = try JSONEncoder().encode(game)
        let restored = try JSONDecoder().decode(SudokuGame.self, from: data)
        XCTAssertEqual(restored, game)
        XCTAssertEqual(restored.hintsUsed, 1)
        XCTAssertTrue(restored.canUndo)
    }

    func testHintsLeadToTheSolution() {
        for p in [SudokuLibrary.all.first { $0.difficulty == .medium }!, SudokuLibrary.all.first { $0.difficulty == .hard }!] {
            var game = SudokuGame(puzzle: p)
            let solution = SudokuSolver.solve(p.cells)!
            var guardCount = 0
            while !game.isSolved, guardCount < 100 {
                guard let hint = game.nextHint() else { break }
                XCTAssertEqual(hint.value, solution[hint.index])
                XCTAssertFalse(hint.explanation.isEmpty)
                game.applyHint(hint)
                guardCount += 1
            }
            XCTAssertTrue(game.isSolved)
            XCTAssertEqual(game.values, solution)
        }
    }

    func testHintPointsOutAMistakeFirst() {
        let p = SudokuLibrary.all[0]
        let solution = SudokuSolver.solve(p.cells)!
        var game = SudokuGame(puzzle: p)
        let i = (0..<81).first { !game.isGiven($0) }!
        game.place(solution[i] % 9 + 1, at: i)
        let hint = game.nextHint()
        XCTAssertEqual(hint?.index, i)
        XCTAssertEqual(hint?.value, solution[i])
    }

    func testNextPuzzleSkipsSolvedOnes() {
        let first = SudokuLibrary.next(difficulty: .medium, excluding: [])!
        let second = SudokuLibrary.next(difficulty: .medium, excluding: [first.id])!
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(SudokuLibrary.next(difficulty: .hard, excluding: Set(SudokuLibrary.all.map(\.id))))
    }
}
