import SwiftUI
import TwelveCore

/// One month's challenge: the reveal, the story, the instructions, the
/// activity itself, and — once finished — the reward and a reflection.
struct ChallengeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let month: Int
    @State private var showActivity = false

    var body: some View {
        NavigationStack {
            Group {
                if let challenge = app.revealedChallenge(month: month) {
                    if app.currentMonth == month && !app.hasWatchedReveal(month: month) {
                        RevealView(challenge: challenge) {
                            withAnimation(.easeInOut(duration: 0.4)) { app.markRevealWatched(month: month) }
                        }
                    } else {
                        ChallengeDetail(challenge: challenge, showActivity: $showActivity)
                    }
                } else {
                    SealedMonthView(month: month)
                }
            }
            .paperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(isPresented: $showActivity) {
                if let challenge = app.revealedChallenge(month: month) {
                    ActivityView(challenge: challenge)
                }
            }
        }
        .onAppear {
            if app.startTimerOnOpen {
                app.startTimerOnOpen = false
                showActivity = true
            }
        }
    }
}

/// Routes a challenge to its reusable activity module.
struct ActivityView: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    var body: some View {
        Group {
            switch challenge.module {
            case .reflection: ReflectionModule(challenge: challenge)
            case .sudoku: SudokuHub(challenge: challenge)
            case .timer, .focus: TimerModule(challenge: challenge)
            case .photos: PhotoModule(challenge: challenge)
            case .reading: ReadingModule(challenge: challenge)
            case .vocabulary: VocabularyModule(challenge: challenge)
            case .creative: CreativeModule(challenge: challenge)
            }
        }
        .paperScreen()
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SealedMonthView: View {
    let month: Int
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            MonthStamp(month: month, state: .sealed, symbol: nil, accent: .gold).frame(width: 150)
            Text("Sealed until 1 \(YearCalendar.monthName(month))")
                .font(.editorial(.title2, weight: .medium)).foregroundStyle(Color.ink)
            Text("Every challenge stays a surprise until its month begins.")
                .font(.subheadline).foregroundStyle(Color.inkSoft).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }
}

/// The physical-feeling moment a new month is opened.
private struct RevealView: View {
    let challenge: ChallengeDefinition
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var angle: Double = 0
    @State private var showText = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Text(challenge.monthName).capsLabel(.accentText)
            ZStack {
                MonthStamp(month: challenge.month, state: .sealed, symbol: nil, accent: .gold)
                    .opacity(opened ? 0 : 1)
                MonthStamp(month: challenge.month, state: .active, symbol: challenge.symbol, accent: .token(challenge.accent))
                    .opacity(opened ? 1 : 0)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(width: 190)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(showText ? 1 : 1.06)
            .onTapGesture { open() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(opened ? challenge.title : "Sealed challenge for \(challenge.monthName). Double tap to open.")

            if showText {
                VStack(spacing: 10) {
                    Text(challenge.title)
                        .font(.editorial(.largeTitle, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    Text(challenge.tagline)
                        .font(.title3)
                        .foregroundStyle(Color.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Your \(challenge.monthName) challenge is ready.")
                    .font(.editorial(.title3)).foregroundStyle(Color.inkSoft)
            }
            Spacer()
            if showText {
                PrimaryButton(title: "See the challenge", systemImage: "arrow.right", action: done)
                    .transition(.opacity)
            } else {
                PrimaryButton(title: "Open \(challenge.monthName)", systemImage: "seal", action: open)
                    .disabled(opened)
            }
        }
        .padding(28)
    }

    private func open() {
        guard !opened else { return }
        Haptics.thud()
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.4)) { opened = true; showText = true }
            return
        }
        withAnimation(.easeIn(duration: 0.28)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            opened = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { angle = 180 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Haptics.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showText = true }
            }
        }
    }
}

private struct ChallengeDetail: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition
    @Binding var showActivity: Bool
    @State private var reflection = ""
    @State private var showTutorial = false

    private var state: MonthState { app.summary.state(month: challenge.month) }

    var body: some View {
        let progress = app.progress(for: challenge)
        let open = app.isOpen(challenge)
        let completed = state == .completed
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top, spacing: 18) {
                    MonthStamp(month: challenge.month, state: completed ? .completed : (open ? .active : state),
                               symbol: challenge.symbol, accent: .token(challenge.accent))
                        .frame(width: 104)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(challenge.monthName) · \(challenge.category)").capsLabel(.accentText)
                        Text(challenge.title)
                            .font(.editorial(.largeTitle, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(challenge.tagline).font(.subheadline).foregroundStyle(Color.inkSoft)
                    }
                }

                // Progress + main action
                FeatureCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 18) {
                            ZStack {
                                ProgressRing(fraction: completed ? 1 : progress.fraction, lineWidth: 8, tint: .gold)
                                Text("\(Int(((completed ? 1 : progress.fraction) * 100).rounded(.down)))%")
                                    .font(.numeral(20, weight: .medium)).foregroundStyle(Color.cream)
                                    .contentTransition(.numericText())
                            }
                            .frame(width: 76, height: 76)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                RollingNumber(text: ProgressCalculator.label(for: challenge, progress: progress),
                                              font: .editorial(.title3, weight: .medium), color: .cream)
                                Text(statusLine(open: open, completed: completed, progress: progress))
                                    .font(.footnote).foregroundStyle(Color.cream.opacity(0.72))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        PrimaryButton(title: actionTitle(open: open, completed: completed, progress: progress), systemImage: "arrow.right") {
                            showActivity = true
                        }
                    }
                }

                // The story
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("The story")
                    Text(challenge.story).font(.editorial(.body)).foregroundStyle(Color.ink).lineSpacing(5)
                    Text(challenge.why).font(.subheadline).italic().foregroundStyle(Color.inkSoft).lineSpacing(3)
                }

                // The explanation
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("How it works")
                    ForEach(Array(challenge.instructions.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(index + 1)").font(.numeral(22, weight: .medium)).foregroundStyle(Color.accentText)
                                .frame(width: 22)
                            Text(line).font(.body).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if challenge.module == .sudoku {
                        SecondaryButton(title: "Play the one-minute tutorial", systemImage: "hand.tap") { showTutorial = true }
                    }
                    if let note = challenge.safetyNote {
                        InfoBanner(symbol: "heart.text.square", text: note, tint: .sageText)
                    }
                }

                if let alt = challenge.accessibleAlternative {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: Binding(get: { app.profile.useAccessibleVariant },
                                                 set: { on in app.updateProfile { $0.useAccessibleVariant = on } })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Another way to do this").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                                    Text(alt.title).font(.footnote).foregroundStyle(Color.inkSoft)
                                }
                            }
                            .tint(.terracotta)
                            Text(alt.detail).font(.footnote).foregroundStyle(Color.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if completed {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Reflection")
                        Text(challenge.reflectionPrompt).font(.editorial(.title3)).foregroundStyle(Color.ink)
                        TextField("A line or two, just for you", text: $reflection, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(14)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                            .onChange(of: reflection) { _, text in
                                app.saveReflection(month: challenge.month, text: text)
                            }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .onAppear { reflection = app.store.stamp(month: challenge.month)?.reflection ?? "" }
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

    private func statusLine(open: Bool, completed: Bool, progress: ChallengeProgress) -> String {
        if completed {
            if let at = app.store.stamp(month: challenge.month)?.completedAt {
                return "Completed \(at.formatted(.dateTime.day().month(.wide)))"
            }
            return "Completed"
        }
        if open {
            if progress.value <= 0 { return "Start whenever you're ready. There's no rush." }
            if challenge.metric == .vocabulary && progress.value >= challenge.target { return "Words learned. The recall exercise is next." }
            return "Nicely under way. Pick it up whenever suits you."
        }
        return "This month is in the archive. What you did is still here."
    }

    private func actionTitle(open: Bool, completed: Bool, progress: ChallengeProgress) -> String {
        if !open { return "Look back" }
        if completed { return "Keep going" }
        return progress.value > 0 ? "Continue" : "Begin"
    }
}

/// The reward: a stamp pressed onto the page, a line of congratulation, and
/// an optional reflection. Restrained on purpose.
struct CelebrationScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let challenge: ChallengeDefinition
    @State private var landed = false
    @State private var showText = false
    @State private var reflection = ""

    var body: some View {
        ZStack {
            Color.espresso.ignoresSafeArea()
            PaperGrain(opacity: 0.06).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Text(challenge.monthName).capsLabel(.gold).padding(.top, 40)
                    MonthStamp(month: challenge.month, state: landed ? .completed : .active, symbol: challenge.symbol,
                               accent: .token(challenge.accent))
                        .frame(width: 200)
                        .scaleEffect(landed || reduceMotion ? 1 : 1.9)
                        .rotationEffect(.degrees(landed || reduceMotion ? -4 : -16))
                        .opacity(landed ? 1 : 0.0)
                        .padding(.vertical, 12)

                    if showText {
                        VStack(spacing: 10) {
                            Text("One more month made meaningful.")
                                .font(.editorial(.largeTitle, weight: .medium))
                                .foregroundStyle(Color.cream)
                                .multilineTextAlignment(.center)
                            Text(challenge.completionLine)
                                .font(.title3).foregroundStyle(Color.cream.opacity(0.75))
                                .multilineTextAlignment(.center)
                            HStack(spacing: 26) {
                                stat("\(app.summary.monthsCompleted)", "of 12 months")
                                stat("\(app.summary.currentStreak)", app.summary.currentStreak == 1 ? "month streak" : "months in a row")
                            }
                            .padding(.top, 10)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("If you'd like to reflect").capsLabel(.gold)
                            Text(challenge.reflectionPrompt).font(.editorial(.title3)).foregroundStyle(Color.cream)
                            TextField("Optional", text: $reflection, axis: .vertical)
                                .lineLimit(2...6)
                                .padding(14)
                                .foregroundStyle(Color.cream)
                                .background(Color.cream.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(.top, 14)
                        .transition(.opacity)

                        PrimaryButton(title: "Add it to my collection", systemImage: "checkmark") {
                            app.saveReflection(month: challenge.month, text: reflection)
                            dismiss()
                        }
                        .padding(.top, 8)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            reflection = app.store.stamp(month: challenge.month)?.reflection ?? ""
            let press = reduceMotion ? Animation.easeIn(duration: 0.3) : Animation.spring(response: 0.42, dampingFraction: 0.58)
            withAnimation(press.delay(0.25)) { landed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                Haptics.thud()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Haptics.success() }
                withAnimation(.easeOut(duration: 0.6).delay(0.2)) { showText = true }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.numeral(40, weight: .medium)).foregroundStyle(Color.gold)
            Text(label).font(.caption).foregroundStyle(Color.cream.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }
}
