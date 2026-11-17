import SwiftUI
import TwelveCore

/// A playful, hands-on introduction on a small 4×4 board.
struct SudokuTutorial: View {
    /// True before the year begins: wording makes clear nothing is recorded.
    let isDemo: Bool
    let finish: () -> Void

    private static let solution = [1, 2, 3, 4,
                                   3, 4, 1, 2,
                                   2, 1, 4, 3,
                                   4, 3, 2, 1]

    private struct Step {
        let cell: Int?
        let highlight: [Int]
        let title: String
        let text: String
        let wrong: String
    }

    private let steps: [Step] = [
        Step(cell: nil, highlight: [], title: "One rule",
             text: "Every row, every column and every square must hold each number exactly once. This little board uses 1 to 4; the real ones use 1 to 9.", wrong: ""),
        Step(cell: 2, highlight: [0, 1, 2, 3], title: "Look along the row",
             text: "This row already has 1, 2 and 4. Which number is missing?", wrong: "That number is already in this row. Which one isn't?"),
        Step(cell: 9, highlight: [1, 5, 9, 13], title: "Now a column",
             text: "This column has 2, 4 and 3. What goes in the gap?", wrong: "That one's already in the column. Look again."),
        Step(cell: 15, highlight: [10, 11, 14, 15], title: "And a square",
             text: "Each square needs every number too. This one has 4, 3 and 2.", wrong: "Already in this square. One number is still missing."),
        Step(cell: 4, highlight: [4, 5, 6, 7, 0, 8, 12, 1], title: "Put it together",
             text: "For the last gap, check its row, its column and its square. Only one number fits.", wrong: "That clashes with a number nearby. Try another."),
    ]

    @State private var values: [Int] = {
        var v = SudokuTutorial.solution
        for i in [2, 9, 15, 4] { v[i] = 0 }
        return v
    }()
    @State private var step = 0
    @State private var message: String?
    @State private var shake = false
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = steps[min(step, steps.count - 1)]
        VStack(spacing: 20) {
            ProgressBar(fraction: done ? 1 : Double(step) / Double(steps.count), tint: .pop, height: 6)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(done ? "That's Sudoku." : current.title)
                    .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(done
                     ? "No arithmetic, no guessing — just ruling things out. A little exercise for the part of your mind that likes figuring things out."
                     : current.text)
                    .font(.body).foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            board(current)
                .offset(x: shake ? -8 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.25), value: shake)

            if let message, !done {
                Text(message).font(.footnote.weight(.medium)).foregroundStyle(Color.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            if done {
                if isDemo {
                    Text("Demonstration only — nothing is recorded until 2027 begins.")
                        .font(.footnote).foregroundStyle(Color.inkSoft)
                }
                PrimaryButton(title: isDemo ? "Done" : "I'm ready", systemImage: "checkmark", action: finish)
            } else if current.cell == nil {
                PrimaryButton(title: "Show me", systemImage: "arrow.right") {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { step += 1 }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(1...4, id: \.self) { digit in
                        Button {
                            answer(digit)
                        } label: {
                            Text("\(digit)")
                                .font(.numeral(30, weight: .medium))
                                .foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                        }
                        .buttonStyle(LiftButtonStyle())
                        .accessibilityLabel("Answer \(digit)")
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .paperScreen()
        .navigationTitle("How Sudoku works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func board(_ current: Step) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 300)
            let cell = side / 4
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cardRaised)
                ForEach(0..<16, id: \.self) { index in
                    let isTarget = current.cell == index && !done
                    let lit = current.highlight.contains(index) && !done
                    ZStack {
                        (isTarget ? Color.lime.opacity(0.6) : (lit ? Color.mint.opacity(0.28) : Color.clear))
                        if values[index] != 0 {
                            Text("\(values[index])")
                                .font(.numeral(cell * 0.5, weight: [2, 9, 15, 4].contains(index) ? .regular : .semibold))
                                .foregroundStyle([2, 9, 15, 4].contains(index) ? Color.accentText : Color.ink)
                                .transition(.scale.combined(with: .opacity))
                        } else if isTarget {
                            Text("?").font(.numeral(cell * 0.45)).foregroundStyle(Color.inkSoft)
                        }
                    }
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(index % 4) * cell, y: CGFloat(index / 4) * cell)
                    .accessibilityElement()
                    .accessibilityLabel("Row \(index / 4 + 1), column \(index % 4 + 1), \(values[index] == 0 ? "empty" : "\(values[index])")\(isTarget ? ", the gap to fill" : "")")
                }
                Canvas { context, size in
                    for i in 0...4 {
                        let p = CGFloat(i) * size.width / 4
                        var path = Path()
                        path.move(to: CGPoint(x: p, y: 0)); path.addLine(to: CGPoint(x: p, y: size.height))
                        path.move(to: CGPoint(x: 0, y: p)); path.addLine(to: CGPoint(x: size.width, y: p))
                        context.stroke(path, with: .color(Color.ink.opacity(i % 2 == 0 ? 0.85 : 0.2)), lineWidth: i % 2 == 0 ? 1.8 : 0.7)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: values)
            .animation(.easeInOut(duration: 0.3), value: step)
        }
        .frame(height: 300)
    }

    private func answer(_ digit: Int) {
        guard step < steps.count, let cell = steps[step].cell else { return }
        if digit == Self.solution[cell] {
            Haptics.success()
            message = nil
            values[cell] = digit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if step + 1 < steps.count { step += 1 } else { done = true }
                }
            }
        } else {
            Haptics.warning()
            withAnimation { message = steps[step].wrong }
            shake = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shake = false }
        }
    }
}
