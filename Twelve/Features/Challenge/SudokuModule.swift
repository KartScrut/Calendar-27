import SwiftUI
import TwelveCore

/// February's home: progress toward five puzzles, games in progress, and
/// a fresh puzzle at either difficulty.
struct SudokuHub: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition
    @State private var activeID: String?
    @State private var showTutorial = false

    var body: some View {
        let _ = app.revision
        let saves = app.store.sudokuSaves()
        let solved = saves.filter { $0.solvedAt != nil }.sorted { ($0.solvedAt ?? .distantPast) > ($1.solvedAt ?? .distantPast) }
        let inProgress = saves.filter { $0.solvedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
        let taken = Set(saves.map(\.puzzleID))
        let open = app.isOpen(challenge)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ModuleProgressHeader(challenge: challenge, progress: app.progress(for: challenge))

                if !open {
                    InfoBanner(symbol: "archivebox", text: "February has closed, so new solves won't change your stamp — but the puzzles are yours to enjoy any time.")
                }

                if !app.profile.hasSeenSudokuTutorial {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("New to Sudoku?").font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                            Text("A one-minute, hands-on introduction. No arithmetic involved.")
                                .font(.subheadline).foregroundStyle(Color.inkSoft)
                            SecondaryButton(title: "Show me how", systemImage: "hand.tap") { showTutorial = true }
                        }
                    }
                }

                if !inProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Pick up where you left off")
                        ForEach(inProgress, id: \.puzzleID) { save in
                            if let puzzle = SudokuLibrary.puzzle(id: save.puzzleID) {
                                puzzleRow(puzzle, detail: "\(save.game?.filledCount ?? 0) of 81 filled", symbol: "pencil.line")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Start a new puzzle")
                    HStack(spacing: 12) {
                        ForEach(SudokuDifficulty.allCases, id: \.self) { difficulty in
                            let next = SudokuLibrary.next(difficulty: difficulty, excluding: taken)
                            Button {
                                if let next { Haptics.tap(); activeID = next.id }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: difficulty == .medium ? "square.grid.3x3" : "square.grid.3x3.fill")
                                        .font(.title2.weight(.light)).foregroundStyle(Color.accentText)
                                    Text(difficulty == .medium ? "Medium" : "Hard").font(.headline).foregroundStyle(Color.ink)
                                    Text(next == nil ? "All played" : (difficulty == .medium ? "Steady logic" : "Takes patience"))
                                        .font(.caption).foregroundStyle(Color.inkSoft)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.hairline))
                            }
                            .buttonStyle(LiftButtonStyle())
                            .disabled(next == nil)
                            .accessibilityLabel("New \(difficulty.rawValue) puzzle")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Solved · \(solved.count)")
                    if solved.isEmpty {
                        EmptyNote(symbol: "checkmark.seal", title: "No puzzles solved yet", message: "Each finished board appears here.")
                    }
                    ForEach(solved, id: \.puzzleID) { save in
                        if let puzzle = SudokuLibrary.puzzle(id: save.puzzleID) {
                            let hints = save.game?.hintsUsed ?? 0
                            puzzleRow(puzzle, detail: (save.solvedAt?.formatted(.dateTime.day().month(.wide)) ?? "")
                                      + (hints > 0 ? " · \(hints) \(hints == 1 ? "hint" : "hints")" : " · no hints"),
                                      symbol: "checkmark.seal.fill")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationDestination(item: $activeID) { id in
            if let puzzle = SudokuLibrary.puzzle(id: id) {
                SudokuBoardScreen(puzzle: puzzle, challenge: challenge) { nextID in activeID = nextID }
                    .id(id)
            }
        }
        .sheet(isPresented: $showTutorial) {
            NavigationStack {
                SudokuTutorial(isDemo: false) {
                    app.updateProfile { $0.hasSeenSudokuTutorial = true }
                    showTutorial = false
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showTutorial = false } } }
            }
        }
    }

    private func puzzleRow(_ puzzle: SudokuPuzzle, detail: String, symbol: String) -> some View {
        Button {
            activeID = puzzle.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentText).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.name(puzzle)).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                    Text(detail).font(.caption).foregroundStyle(Color.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSoft)
            }
            .padding(16)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline))
        }
        .buttonStyle(LiftButtonStyle())
    }

    static func name(_ puzzle: SudokuPuzzle) -> String {
        let number = Int(puzzle.id.dropFirst()) ?? 0
        return "\(puzzle.difficulty == .medium ? "Medium" : "Hard") · No. \(number)"
    }
}

/// The playable board.
struct SudokuBoardScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let puzzle: SudokuPuzzle
    let challenge: ChallengeDefinition
    let openNext: (String?) -> Void

    @State private var game: SudokuGame
    @State private var selected: Int?
    @State private var notesMode = false
    @State private var hintText: String?
    @State private var hintCell: Int?
    @State private var solved = false
    @State private var wave = false
    @State private var wasAlreadySolved = false
    @State private var sessionStart = Date()

    init(puzzle: SudokuPuzzle, challenge: ChallengeDefinition, openNext: @escaping (String?) -> Void) {
        self.puzzle = puzzle
        self.challenge = challenge
        self.openNext = openNext
        _game = State(initialValue: SudokuGame(puzzle: puzzle))
    }

    var body: some View {
        let conflicts = game.conflicts
        VStack(spacing: 14) {
            HStack {
                Text(SudokuHub.name(puzzle)).capsLabel(.accentText)
                Spacer()
                Text("\(81 - game.filledCount) to fill").font(.caption.weight(.semibold)).foregroundStyle(Color.inkSoft)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            SudokuGrid(game: game, selected: selected, conflicts: conflicts, hintCell: hintCell, wave: wave) { index in
                Haptics.select()
                selected = index
                hintCell = nil
            }

            Group {
                if let hintText {
                    Text(hintText)
                        .font(.footnote)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.lime.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity)
                } else if !conflicts.isEmpty {
                    Label("A number repeats in a row, column or square. The marked cells clash.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.pop.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: hintText)

            Spacer(minLength: 0)

            if solved {
                solvedPanel
            } else {
                controls
                numberPad
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .paperScreen()
        .navigationTitle("Sudoku")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: persist)
    }

    // MARK: Controls

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                tool("Undo", "arrow.uturn.backward", enabled: game.canUndo) { edit { $0.undo() } }
                tool("Redo", "arrow.uturn.forward", enabled: game.canRedo) { edit { $0.redo() } }
                tool("Erase", "eraser", enabled: selected.map { !game.isGiven($0) } ?? false) {
                    if let s = selected { edit { $0.erase(at: s) } }
                }
                Button {
                    notesMode.toggle()
                    Haptics.select()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: notesMode ? "pencil.circle.fill" : "pencil.circle").font(.title3)
                        Text("Notes").font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .tint(notesMode ? .pop : nil)
                .accessibilityLabel("Pencil notes")
                .accessibilityValue(notesMode ? "On" : "Off")
                tool("Hint", "lightbulb", enabled: true, action: hint)
            }
        }
    }

    private func tool(_ title: String, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    private var numberPad: some View {
        HStack(spacing: 6) {
            ForEach(1...9, id: \.self) { digit in
                let remaining = 9 - game.count(of: digit)
                Button {
                    enter(digit)
                } label: {
                    VStack(spacing: 0) {
                        Text("\(digit)").font(.numeral(26, weight: .medium))
                        Text(remaining > 0 ? "\(remaining)" : " ").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.inkSoft)
                    }
                    .foregroundStyle(remaining > 0 ? Color.ink : Color.inkSoft.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
                }
                .buttonStyle(LiftButtonStyle())
                .disabled(selected == nil || (remaining <= 0 && !notesMode))
                .accessibilityLabel("\(digit)")
                .accessibilityHint(remaining > 0 ? "\(remaining) left to place" : "All placed")
            }
        }
    }

    private var solvedPanel: some View {
        let count = Int(app.progress(for: challenge).value)
        let target = Int(challenge.target)
        let taken = Set(app.store.sudokuSaves().map(\.puzzleID))
        let next = SudokuLibrary.next(difficulty: puzzle.difficulty, excluding: taken)
        return VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(Color.limeText)
            Text("Solved.").font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
            if app.isOpen(challenge) || app.summary.state(month: challenge.month) == .completed {
                Text(count >= target ? "That's all \(target). February is complete." : "\(count) of \(target) puzzles done. \(target - count) to go.")
                    .font(.subheadline).foregroundStyle(Color.inkSoft)
            }
            if let next, !wasAlreadySolved {
                PrimaryButton(title: "Next puzzle", systemImage: "arrow.right") { openNext(next.id) }
            }
            SecondaryButton(title: "Back to puzzles", systemImage: nil) { dismiss() }
        }
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Actions

    private func load() {
        sessionStart = Date()
        if let save = app.store.sudokuSave(puzzleID: puzzle.id), let saved = save.game {
            game = saved
            if save.solvedAt != nil {
                solved = true
                wasAlreadySolved = true
            }
        }
        if selected == nil { selected = (0..<81).first { game.values[$0] == 0 } }
    }

    private func persist() {
        guard !wasAlreadySolved else { return }
        game.elapsedSeconds += Date().timeIntervalSince(sessionStart)
        sessionStart = Date()
        app.saveSudoku(game)
    }

    private func edit(_ change: (inout SudokuGame) -> Void) {
        guard !solved else { return }
        var copy = game
        change(&copy)
        game = copy
        hintText = nil
        hintCell = nil
        Haptics.tap()
        afterChange()
    }

    private func enter(_ digit: Int) {
        guard let s = selected, !solved else { return }
        if game.isGiven(s) { Haptics.warning(); return }
        if notesMode {
            edit { $0.toggleNote(digit, at: s) }
        } else {
            edit { $0.place(digit, at: s) }
        }
    }

    private func hint() {
        guard !solved, let h = game.nextHint(preferring: selected) else { return }
        var copy = game
        copy.applyHint(h)
        game = copy
        selected = h.index
        hintCell = h.index
        hintText = h.explanation
        Haptics.select()
        afterChange()
    }

    /// Saves after every move, and finishes the puzzle only when the whole
    /// board is correct.
    private func afterChange() {
        if game.isSolved {
            game.elapsedSeconds += Date().timeIntervalSince(sessionStart)
            app.saveSudoku(game)
            Haptics.success()
            hintText = nil
            selected = nil
            if reduceMotion {
                solved = true
            } else {
                wave = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { solved = true }
                }
            }
        } else {
            app.saveSudoku(game)
        }
    }
}

/// The 9×9 grid.
struct SudokuGrid: View {
    let game: SudokuGame
    let selected: Int?
    let conflicts: Set<Int>
    let hintCell: Int?
    let wave: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        let selectedValue = selected.map { game.values[$0] } ?? 0
        let related: Set<Int> = selected.map { Set(SudokuSolver.peers[$0]) } ?? []
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 9
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.cardRaised)
                ForEach(0..<81, id: \.self) { index in
                    let row = index / 9, col = index % 9
                    SudokuCell(value: game.values[index], notes: game.notes[index], isGiven: game.isGiven(index),
                               isSelected: selected == index, isRelated: related.contains(index),
                               sameDigit: selectedValue != 0 && game.values[index] == selectedValue,
                               isConflict: conflicts.contains(index), isHint: hintCell == index,
                               wave: wave, waveDelay: Double(row + col) * 0.045, size: cell)
                        .frame(width: cell, height: cell)
                        .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
                        .onTapGesture { onSelect(index) }
                        .accessibilityElement()
                        .accessibilityLabel(label(index))
                        .accessibilityAddTraits(selected == index ? [.isButton, .isSelected] : .isButton)
                }
                // Grid lines: thin for cells, heavy for the nine squares.
                Canvas { context, size in
                    for i in 0...9 {
                        let p = CGFloat(i) * size.width / 9
                        let heavy = i % 3 == 0
                        var path = Path()
                        path.move(to: CGPoint(x: p, y: 0)); path.addLine(to: CGPoint(x: p, y: size.height))
                        path.move(to: CGPoint(x: 0, y: p)); path.addLine(to: CGPoint(x: size.width, y: p))
                        context.stroke(path, with: .color(heavy ? Color.ink.opacity(0.85) : Color.ink.opacity(0.18)),
                                       lineWidth: heavy ? 1.6 : 0.6)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func label(_ index: Int) -> String {
        let value = game.values[index]
        var parts = ["Row \(index / 9 + 1), column \(index % 9 + 1)"]
        if value == 0 {
            let notes = (1...9).filter { game.hasNote($0, at: index) }
            parts.append(notes.isEmpty ? "empty" : "notes \(notes.map(String.init).joined(separator: ", "))")
        } else {
            parts.append("\(value)")
            parts.append(game.isGiven(index) ? "given" : "your entry")
            if conflicts.contains(index) { parts.append("clashes with another cell") }
        }
        return parts.joined(separator: ", ")
    }
}

private struct SudokuCell: View {
    let value: Int
    let notes: UInt16
    let isGiven: Bool
    let isSelected: Bool
    let isRelated: Bool
    let sameDigit: Bool
    let isConflict: Bool
    let isHint: Bool
    let wave: Bool
    let waveDelay: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            background
            Color.lime.opacity(wave ? 0.5 : 0)
                .animation(.easeInOut(duration: 0.35).delay(waveDelay), value: wave)
            if value != 0 {
                Text("\(value)")
                    .font(.numeral(size * 0.56, weight: isGiven ? .semibold : .regular))
                    .foregroundStyle(isGiven ? Color.ink : Color.accentText)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                if isConflict {
                    // A mark as well as a colour, so clashes don't rely on colour alone.
                    Circle().fill(Color.pop).frame(width: size * 0.14, height: size * 0.14)
                        .offset(x: size * 0.32, y: -size * 0.32)
                }
            } else if notes != 0 {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(1...3, id: \.self) { c in
                                let d = r * 3 + c
                                Text(notes & (1 << UInt16(d)) != 0 ? "\(d)" : " ")
                                    .font(.system(size: size * 0.24, weight: .medium))
                                    .foregroundStyle(Color.inkSoft)
                                    .frame(width: size / 3.3, height: size / 3.3)
                            }
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: value)
    }

    private var background: Color {
        if isSelected { return Color.lime.opacity(0.55) }
        if isHint { return Color.lime.opacity(0.35) }
        if isConflict { return Color.pop.opacity(0.22) }
        if sameDigit { return Color.lime.opacity(0.28) }
        if isRelated { return Color.leaf.opacity(0.2) }
        return .clear
    }
}
