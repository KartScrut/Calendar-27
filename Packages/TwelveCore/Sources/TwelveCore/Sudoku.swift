import Foundation

public enum SudokuDifficulty: String, Codable, Sendable, CaseIterable {
    case medium, hard
}

/// A puzzle from the validated library. `givens` is 81 characters, row by row,
/// with "0" for an empty cell.
public struct SudokuPuzzle: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let difficulty: SudokuDifficulty
    public let givens: String

    public init(id: String, difficulty: SudokuDifficulty, givens: String) {
        self.id = id
        self.difficulty = difficulty
        self.givens = givens
    }

    public var cells: [Int] { givens.compactMap { $0.wholeNumberValue } }
}

public enum SudokuLibrary {
    public static let all: [SudokuPuzzle] = CoreResources.decode("puzzles") ?? []

    public static func puzzle(id: String) -> SudokuPuzzle? { all.first { $0.id == id } }

    /// The next puzzle to offer: an unsolved one of the requested difficulty.
    public static func next(difficulty: SudokuDifficulty, excluding solved: Set<String>) -> SudokuPuzzle? {
        all.first { $0.difficulty == difficulty && !solved.contains($0.id) }
    }
}

/// Pure Sudoku rules and a fast bitmask solver.
public enum SudokuSolver {
    /// Indices of the 20 cells that share a row, column or box with each cell.
    public static let peers: [[Int]] = (0..<81).map { i in
        let r = i / 9, c = i % 9
        var set = Set<Int>()
        for k in 0..<9 { set.insert(r * 9 + k); set.insert(k * 9 + c) }
        let br = r / 3 * 3, bc = c / 3 * 3
        for dr in 0..<3 { for dc in 0..<3 { set.insert((br + dr) * 9 + bc + dc) } }
        set.remove(i)
        return set.sorted()
    }

    /// The 27 units: 9 rows, 9 columns, 9 boxes.
    public static let units: [[Int]] = {
        var u: [[Int]] = []
        for r in 0..<9 { u.append((0..<9).map { r * 9 + $0 }) }
        for c in 0..<9 { u.append((0..<9).map { $0 * 9 + c }) }
        for b in 0..<9 {
            var cells: [Int] = []
            for dr in 0..<3 { for dc in 0..<3 { cells.append((b / 3 * 3 + dr) * 9 + b % 3 * 3 + dc) } }
            u.append(cells)
        }
        return u
    }()

    /// Bitmask of digits (bit d set = digit d allowed) for an empty cell.
    public static func candidates(in grid: [Int], at index: Int) -> UInt16 {
        var mask: UInt16 = 0b11_1111_1110
        for p in peers[index] where grid[p] != 0 { mask &= ~(1 << UInt16(grid[p])) }
        return mask
    }

    /// True when no row, column or box repeats a digit (empty cells allowed).
    public static func isConsistent(_ grid: [Int]) -> Bool {
        guard grid.count == 81 else { return false }
        for unit in units {
            var seen: UInt16 = 0
            for i in unit {
                let v = grid[i]
                guard (0...9).contains(v) else { return false }
                if v == 0 { continue }
                let bit: UInt16 = 1 << UInt16(v)
                if seen & bit != 0 { return false }
                seen |= bit
            }
        }
        return true
    }

    /// Cells whose value clashes with a peer.
    public static func conflicts(in grid: [Int]) -> Set<Int> {
        var out = Set<Int>()
        for i in 0..<81 where grid[i] != 0 {
            for p in peers[i] where grid[p] == grid[i] { out.insert(i); break }
        }
        return out
    }

    /// Counts solutions up to `limit` (use 2 to test uniqueness).
    public static func countSolutions(_ start: [Int], limit: Int = 2) -> Int {
        guard start.count == 81, isConsistent(start) else { return 0 }
        var grid = start
        var count = 0
        search(&grid, &count, limit, nil)
        return count
    }

    public static func solve(_ start: [Int]) -> [Int]? {
        guard start.count == 81, isConsistent(start) else { return nil }
        var grid = start
        var count = 0
        var result: [Int]?
        search(&grid, &count, 1) { result = $0 }
        return result
    }

    public static func hasUniqueSolution(_ grid: [Int]) -> Bool { countSolutions(grid, limit: 2) == 1 }

    private static func search(_ grid: inout [Int], _ count: inout Int, _ limit: Int, _ onSolution: (([Int]) -> Void)?) {
        // Choose the empty cell with the fewest candidates (MRV).
        var best = -1
        var bestMask: UInt16 = 0
        var bestCount = 10
        for i in 0..<81 where grid[i] == 0 {
            let mask = candidates(in: grid, at: i)
            let n = mask.nonzeroBitCount
            if n == 0 { return }
            if n < bestCount {
                best = i; bestMask = mask; bestCount = n
                if n == 1 { break }
            }
        }
        if best < 0 {
            count += 1
            onSolution?(grid)
            return
        }
        for d in 1...9 where bestMask & (1 << UInt16(d)) != 0 {
            grid[best] = d
            search(&grid, &count, limit, onSolution)
            grid[best] = 0
            if count >= limit { return }
        }
    }
}

public struct SudokuHint: Equatable, Sendable {
    public let index: Int
    public let value: Int
    public let explanation: String
}

/// The full, saveable state of one game in progress.
public struct SudokuGame: Codable, Equatable, Sendable {
    public struct Move: Codable, Equatable, Sendable {
        public let index: Int
        public let oldValue: Int
        public let newValue: Int
        public let oldNotes: UInt16
        public let newNotes: UInt16
    }

    public let puzzleID: String
    public let givens: [Int]
    public private(set) var values: [Int]
    /// Pencil marks per cell as a bitmask (bit d = digit d noted).
    public private(set) var notes: [UInt16]
    public private(set) var undoStack: [Move] = []
    public private(set) var redoStack: [Move] = []
    public private(set) var hintsUsed = 0
    public var elapsedSeconds: Double = 0

    public init(puzzle: SudokuPuzzle) {
        puzzleID = puzzle.id
        var cells = puzzle.cells
        if cells.count != 81 { cells = Array(repeating: 0, count: 81) }
        givens = cells
        values = cells
        notes = Array(repeating: 0, count: 81)
    }

    /// For tutorials and tests.
    public init(puzzleID: String, givens: [Int]) {
        self.puzzleID = puzzleID
        self.givens = givens
        self.values = givens
        self.notes = Array(repeating: 0, count: givens.count)
    }

    public func isGiven(_ index: Int) -> Bool { givens[index] != 0 }

    public var filledCount: Int { values.filter { $0 != 0 }.count }

    public var conflicts: Set<Int> { SudokuSolver.conflicts(in: values) }

    /// Solved means: every cell filled, no rule broken, and the givens untouched.
    /// For a unique-solution puzzle that is exactly the one correct board.
    public var isSolved: Bool {
        guard values.count == 81, !values.contains(0), SudokuSolver.isConsistent(values) else { return false }
        for i in 0..<81 where givens[i] != 0 && givens[i] != values[i] { return false }
        return true
    }

    public func count(of digit: Int) -> Int { values.filter { $0 == digit }.count }

    // MARK: Editing

    private mutating func apply(_ move: Move, record: Bool) {
        values[move.index] = move.newValue
        notes[move.index] = move.newNotes
        if record {
            undoStack.append(move)
            if undoStack.count > 400 { undoStack.removeFirst(undoStack.count - 400) }
            redoStack.removeAll()
        }
    }

    /// Places a digit (1...9). Placing the digit already there clears the cell.
    public mutating func place(_ digit: Int, at index: Int) {
        guard (1...9).contains(digit), values.indices.contains(index), !isGiven(index) else { return }
        let new = values[index] == digit ? 0 : digit
        apply(Move(index: index, oldValue: values[index], newValue: new, oldNotes: notes[index], newNotes: 0), record: true)
    }

    public mutating func toggleNote(_ digit: Int, at index: Int) {
        guard (1...9).contains(digit), values.indices.contains(index), !isGiven(index), values[index] == 0 else { return }
        let new = notes[index] ^ (1 << UInt16(digit))
        apply(Move(index: index, oldValue: 0, newValue: 0, oldNotes: notes[index], newNotes: new), record: true)
    }

    public mutating func erase(at index: Int) {
        guard values.indices.contains(index), !isGiven(index), values[index] != 0 || notes[index] != 0 else { return }
        apply(Move(index: index, oldValue: values[index], newValue: 0, oldNotes: notes[index], newNotes: 0), record: true)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func undo() {
        guard let m = undoStack.popLast() else { return }
        values[m.index] = m.oldValue
        notes[m.index] = m.oldNotes
        redoStack.append(m)
    }

    public mutating func redo() {
        guard let m = redoStack.popLast() else { return }
        values[m.index] = m.newValue
        notes[m.index] = m.newNotes
        undoStack.append(m)
    }

    public func hasNote(_ digit: Int, at index: Int) -> Bool { notes[index] & (1 << UInt16(digit)) != 0 }

    // MARK: Hints

    /// Finds a helpful next step. Prefers a cell that can be reasoned out and
    /// explains why; falls back to revealing a cell from the solution.
    public func nextHint(preferring selected: Int? = nil) -> SudokuHint? {
        guard values.count == 81, let solution = SudokuSolver.solve(givens) else { return nil }
        // A wrong entry blocks all reasoning, so point at it first.
        for i in 0..<81 where !isGiven(i) && values[i] != 0 && values[i] != solution[i] {
            return SudokuHint(index: i, value: solution[i],
                              explanation: "This cell can't stay as \(values[i]). It needs to be \(solution[i]).")
        }
        // Naked single: only one digit fits.
        for i in 0..<81 where values[i] == 0 {
            let mask = SudokuSolver.candidates(in: values, at: i)
            if mask.nonzeroBitCount == 1 {
                let d = mask.trailingZeroBitCount
                return SudokuHint(index: i, value: d,
                                  explanation: "Every other number already appears in this cell's row, column or square. Only \(d) fits.")
            }
        }
        // Hidden single: a digit has only one home in a unit.
        let names = ["row", "column", "square"]
        for (u, unit) in SudokuSolver.units.enumerated() {
            for d in 1...9 {
                if unit.contains(where: { values[$0] == d }) { continue }
                let spots = unit.filter { values[$0] == 0 && SudokuSolver.candidates(in: values, at: $0) & (1 << UInt16(d)) != 0 }
                if spots.count == 1 {
                    return SudokuHint(index: spots[0], value: d,
                                      explanation: "In this \(names[u / 9]), \(d) has only one place left to go.")
                }
            }
        }
        let target = (selected.flatMap { values[$0] == 0 ? $0 : nil }) ?? (0..<81).first { values[$0] == 0 }
        guard let t = target else { return nil }
        return SudokuHint(index: t, value: solution[t], explanation: "This one takes a longer chain of reasoning. It's \(solution[t]).")
    }

    /// Applies a hint and counts it.
    public mutating func applyHint(_ hint: SudokuHint) {
        guard values.indices.contains(hint.index), !isGiven(hint.index) else { return }
        apply(Move(index: hint.index, oldValue: values[hint.index], newValue: hint.value,
                   oldNotes: notes[hint.index], newNotes: 0), record: true)
        hintsUsed += 1
    }
}
