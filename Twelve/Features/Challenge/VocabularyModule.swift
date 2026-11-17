import SwiftUI
import TwelveCore

/// June: learn twelve words, then show you can recall them.
struct VocabularyModule: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    private enum Mode { case cards, quiz }
    @State private var mode: Mode = .cards
    @State private var index = 0
    @State private var flipped = false

    var body: some View {
        let _ = app.revision
        let language = app.profile.vocabularyLanguage.flatMap(Vocabulary.language)
        let progress = app.progress(for: challenge)
        let open = app.isOpen(challenge)

        Group {
            if let language {
                let learned = Set(app.entries(for: challenge).compactMap(\.ref))
                switch mode {
                case .cards:
                    cards(language: language, learned: learned, progress: progress, open: open)
                case .quiz:
                    RecallQuiz(language: language) { passed in
                        if passed, open, !progress.quizPassed {
                            app.log(challenge, kind: ProgressCalculator.quizPassKind)
                        }
                    } close: {
                        mode = .cards
                    }
                }
            } else {
                languagePicker(open: open)
            }
        }
    }

    private func languagePicker(open: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a language").font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                Text("Twelve everyday words — enough to say hello, please and thank you.")
                    .font(.subheadline).foregroundStyle(Color.inkSoft)
                ForEach(Vocabulary.languages) { language in
                    Button {
                        Haptics.select()
                        app.updateProfile { $0.vocabularyLanguage = language.id }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.name).font(.editorial(.title2, weight: .medium)).foregroundStyle(Color.ink)
                                Text(language.nativeName).font(.subheadline).foregroundStyle(Color.inkSoft)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(Color.accentText)
                        }
                        .padding(18)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.hairline))
                    }
                    .buttonStyle(LiftButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func cards(language: VocabularyLanguage, learned: Set<String>, progress: ChallengeProgress, open: Bool) -> some View {
        let words = language.words
        let word = words[min(index, words.count - 1)]
        let isLearned = learned.contains(word.id)
        let allLearned = learned.count >= Vocabulary.wordsToLearn
        ScrollView {
            VStack(spacing: 20) {
                ModuleProgressHeader(challenge: challenge, progress: progress)
                HStack {
                    Tag(text: language.name, systemImage: "character.bubble", tint: .mintText)
                    Spacer()
                    if learned.isEmpty {
                        Button("Change language") { app.updateProfile { $0.vocabularyLanguage = nil } }
                            .font(.footnote).foregroundStyle(Color.accentText)
                    }
                    Text("\(index + 1) / \(words.count)").font(.caption.weight(.semibold)).foregroundStyle(Color.inkSoft)
                }

                // Flashcard
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped.toggle() }
                    Haptics.tap()
                } label: {
                    VStack(spacing: 14) {
                        if flipped {
                            Text(word.meaning).font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                            Text(word.example).font(.title3).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                            Text(word.exampleMeaning).font(.subheadline).foregroundStyle(Color.inkSoft).multilineTextAlignment(.center)
                        } else {
                            Text(word.word).font(.numeral(48, weight: .medium)).foregroundStyle(Color.ink)
                                .minimumScaleFactor(0.5).lineLimit(2).multilineTextAlignment(.center)
                            Text("Tap to see what it means").font(.footnote).foregroundStyle(Color.inkSoft)
                        }
                        if isLearned { Tag(text: "Learned", systemImage: "checkmark", tint: .mintText) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .padding(24)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.hairline))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
                }
                .buttonStyle(LiftButtonStyle())
                .accessibilityLabel(flipped ? "\(word.word) means \(word.meaning). Example: \(word.exampleMeaning)" : "\(word.word). Double tap to see the meaning.")

                HStack(spacing: 12) {
                    Button {
                        Speaker.shared.speak(word.word, languageCode: language.speechCode)
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .disabled(!Speaker.shared.canSpeak(language.speechCode))
                    Button {
                        step(-1, count: words.count)
                    } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 36, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Previous word")
                    Button {
                        step(1, count: words.count)
                    } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 36, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Next word")
                }
                if !Speaker.shared.canSpeak(language.speechCode) {
                    Text("No \(language.name) voice is installed on this iPhone, so audio is unavailable.")
                        .font(.caption).foregroundStyle(Color.inkSoft)
                }

                if open && !isLearned {
                    PrimaryButton(title: "I've got this one", systemImage: "checkmark") {
                        if app.log(challenge, ref: word.id, title: word.word) != nil { Haptics.success() }
                        step(1, count: words.count)
                    }
                    .disabled(!flipped)
                }

                PaperCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Recall exercise")
                        Text(progress.quizPassed
                             ? "Passed. You can retake it any time to keep the words fresh."
                             : (allLearned ? "You've studied all twelve. Ready to see how many you remember? You need \(Vocabulary.passMark) of \(Vocabulary.wordsToLearn)."
                                           : "Study all twelve words first. Then show you can recall at least \(Vocabulary.passMark) of them."))
                            .font(.subheadline).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                        SecondaryButton(title: allLearned ? (progress.quizPassed ? "Practise again" : "Start the recall exercise") : "Practice round",
                                        systemImage: "brain.head.profile") {
                            mode = .quiz
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func step(_ delta: Int, count: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            index = (index + delta + count) % count
            flipped = false
        }
        Haptics.select()
    }
}

/// Twelve questions: a meaning is shown, and the right word must be chosen.
private struct RecallQuiz: View {
    let language: VocabularyLanguage
    let finished: (Bool) -> Void
    let close: () -> Void

    @State private var questions: [RecallQuestion] = []
    @State private var position = 0
    @State private var correct = 0
    @State private var chosen: Int?
    @State private var done = false

    var body: some View {
        VStack(spacing: 22) {
            if done {
                let passed = Vocabulary.passed(correct: correct, total: questions.count)
                Spacer()
                Image(systemName: passed ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 52, weight: .light)).foregroundStyle(passed ? Color.limeText : Color.accentText)
                Text("\(correct) of \(questions.count)").font(.numeral(56, weight: .medium)).foregroundStyle(Color.ink)
                Text(passed ? "You remembered them. That's the recall exercise passed."
                            : "Nearly. You need \(Vocabulary.passMark) to pass — another look at the cards, then try again.")
                    .font(.body).foregroundStyle(Color.inkSoft).multilineTextAlignment(.center)
                Spacer()
                if !passed {
                    PrimaryButton(title: "Try again", systemImage: "arrow.clockwise") { start() }
                }
                SecondaryButton(title: "Back to the cards", systemImage: nil, action: close)
            } else if questions.indices.contains(position) {
                let q = questions[position]
                ProgressBar(fraction: Double(position) / Double(questions.count), tint: .pop, height: 6)
                VStack(spacing: 8) {
                    Text("Which word means").capsLabel()
                    Text(q.meaning).font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .accessibilityElement(children: .combine)
                VStack(spacing: 10) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                        let reveal = chosen != nil
                        let isRight = i == q.answer
                        Button {
                            choose(i)
                        } label: {
                            HStack {
                                Text(option).font(.title3.weight(.medium))
                                Spacer()
                                if reveal && isRight { Image(systemName: "checkmark.circle.fill") }
                                if reveal && chosen == i && !isRight { Image(systemName: "xmark.circle") }
                            }
                            .foregroundStyle(Color.ink)
                            .padding(18)
                            .background(reveal && isRight ? Color.mint.opacity(0.4) : (reveal && chosen == i ? Color.pop.opacity(0.22) : Color.card),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline))
                        }
                        .buttonStyle(LiftButtonStyle())
                        .disabled(reveal)
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .onAppear(perform: start)
    }

    private func start() {
        questions = Vocabulary.quiz(words: language.words, seed: UUID().uuidString)
        position = 0
        correct = 0
        chosen = nil
        done = false
    }

    private func choose(_ i: Int) {
        guard chosen == nil, questions.indices.contains(position) else { return }
        chosen = i
        let right = i == questions[position].answer
        if right { correct += 1; Haptics.success() } else { Haptics.warning() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (right ? 0.6 : 1.3)) {
            withAnimation(.easeInOut(duration: 0.25)) {
                chosen = nil
                if position + 1 < questions.count {
                    position += 1
                } else {
                    done = true
                    finished(Vocabulary.passed(correct: correct, total: questions.count))
                }
            }
        }
    }
}
