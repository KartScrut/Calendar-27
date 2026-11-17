import SwiftUI
import TwelveCore

/// The daily home: the date, this month's challenge, today's Spark, a small
/// optional activity, and the collection so far.
struct TodayScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch app.phase {
                    case .prelaunch(let days):
                        PrelaunchContent(days: days)
                    case .active(let month, let day):
                        DateHeader(month: month, day: day)
                        if app.storageFailed {
                            InfoBanner(symbol: "exclamationmark.triangle", text: "TWELVE couldn't open its storage, so changes won't be kept this session. Restarting the app usually fixes it.", tint: .accentText)
                        }
                        if app.isDemo {
                            InfoBanner(symbol: "wand.and.stars", text: "Preview mode: a simulated date with separate demo data. Nothing here counts toward the real year.", tint: .goldText)
                        }
                        ChallengeCard(month: month)
                        SparkCard()
                        MicroCard()
                        CollectionStrip()
                    case .ended:
                        EndedContent()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .paperScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// "17 · Wednesday · November" in large editorial type, with year progress.
private struct DateHeader: View {
    @Environment(AppModel.self) private var app
    let month: Int
    let day: Int

    var body: some View {
        let weekday = YearCalendar.weekdayNames[app.calendar.weekdayIndex(for: app.now)]
        let dayOfYear = app.calendar.dayOfYear(at: app.now)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekday).capsLabel(.accentText)
                Spacer()
                Text("2027").capsLabel()
            }
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(YearCalendar.twoDigit(day))
                    .font(.numeral(96, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(YearCalendar.monthName(month))
                    .font(.editorial(.title, weight: .regular))
                    .italic()
                    .foregroundStyle(Color.ink)
                    .padding(.bottom, 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(weekday), \(day) \(YearCalendar.monthName(month)) 2027")
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                ProgressBar(fraction: app.calendar.yearProgress(at: app.now), tint: .gold, height: 4)
                Text("Day \(dayOfYear) of \(app.calendar.daysInYear)")
                    .font(.caption).foregroundStyle(Color.inkSoft)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(dayOfYear) of \(app.calendar.daysInYear) in 2027")
        }
        .padding(.top, 12)
    }
}

/// The current monthly challenge: sealed until opened, then live progress.
private struct ChallengeCard: View {
    @Environment(AppModel.self) private var app
    let month: Int

    var body: some View {
        if let challenge = app.revealedChallenge(month: month) {
            let watched = app.hasWatchedReveal(month: month)
            let progress = app.progress(for: challenge)
            let done = app.summary.state(month: month) == .completed
            Button {
                Haptics.tap()
                app.sheet = .challenge(month: month)
            } label: {
                FeatureCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("\(YearCalendar.monthName(month)) · Challenge \(YearCalendar.twoDigit(month))").capsLabel(.gold)
                            Spacer()
                            if done { Tag(text: "Complete", systemImage: "checkmark", tint: .gold) }
                        }
                        if watched {
                            HStack(alignment: .center, spacing: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(challenge.title)
                                        .font(.editorial(.title, weight: .medium))
                                        .foregroundStyle(Color.cream)
                                        .multilineTextAlignment(.leading)
                                    Text(challenge.tagline)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.cream.opacity(0.72))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                ZStack {
                                    ProgressRing(fraction: done ? 1 : progress.fraction, lineWidth: 7, tint: .gold)
                                    Image(systemName: done ? "checkmark" : challenge.symbol)
                                        .font(.title3.weight(done ? .bold : .light))
                                        .foregroundStyle(Color.cream)
                                }
                                .frame(width: 68, height: 68)
                            }
                            HStack {
                                RollingNumber(text: done ? challenge.completionLine : ProgressCalculator.label(for: challenge, progress: progress),
                                              font: .subheadline.weight(.semibold), color: .cream)
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(Color.gold)
                            }
                        } else {
                            HStack(spacing: 18) {
                                MonthStamp(month: month, state: .sealed, symbol: nil, accent: .gold, showsName: false)
                                    .frame(width: 64)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(YearCalendar.monthName(month)) has arrived.")
                                        .font(.editorial(.title2, weight: .medium)).foregroundStyle(Color.cream)
                                    Text("Your next challenge is ready to open.")
                                        .font(.subheadline).foregroundStyle(Color.cream.opacity(0.72))
                                }
                            }
                            HStack {
                                Text("Reveal").font(.subheadline.weight(.semibold)).foregroundStyle(Color.gold)
                                Image(systemName: "arrow.right").foregroundStyle(Color.gold)
                            }
                        }
                    }
                }
            }
            .buttonStyle(LiftButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(watched ? "Opens this month's challenge" : "Reveals this month's challenge")
        }
    }
}

/// Today's Spark, as a small magazine teaser.
private struct SparkCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let card = app.spark {
            let category = Interests.category(card.category)
            let _ = app.revision
            let answered = app.store.interaction(cardID: card.id)?.answeredAt != nil
            Button {
                Haptics.tap()
                app.sheet = .spark
            } label: {
                PaperCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel("Today's Spark", color: .accentText)
                            Spacer()
                            if let category { Tag(text: category.name, systemImage: category.symbol, tint: .sageText) }
                        }
                        Text(card.headline)
                            .font(.editorial(.title2, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Text(card.body)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(answered ? "Read again" : "Read · about a minute").font(.footnote.weight(.semibold))
                            Image(systemName: "arrow.right").font(.footnote.weight(.semibold))
                            Spacer()
                            if answered { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.sageText) }
                        }
                        .foregroundStyle(Color.accentText)
                        .padding(.top, 2)
                    }
                }
            }
            .buttonStyle(LiftButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens today's discovery")
        }
    }
}

/// The optional one-to-five-minute activity.
private struct MicroCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let micro = app.micro {
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel("A small extra · optional")
                        Spacer()
                        Text("\(micro.minutes) min").font(.caption.weight(.semibold)).foregroundStyle(Color.inkSoft)
                    }
                    Text(micro.title).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                    Text(micro.detail).font(.subheadline).foregroundStyle(Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.microDone {
                        Label("Done today · +\(Points.microChallenge) discovery points", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.sageText)
                            .padding(.top, 4)
                    } else {
                        Button {
                            Haptics.success()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { app.completeMicro() }
                        } label: {
                            Label("I did this", systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

/// A glance at the year's stamps.
private struct CollectionStrip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Your year so far")
                Spacer()
                Button {
                    app.tab = .calendar
                    app.showYearOverview = true
                } label: {
                    Text("See all").font(.footnote.weight(.semibold)).foregroundStyle(Color.accentText)
                }
            }
            HStack(spacing: 18) {
                stat("\(app.summary.monthsCompleted)", "of 12 months")
                stat("\(app.summary.currentStreak)", "month streak")
                stat("\(app.points)", "discovery points")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(1...12, id: \.self) { month in
                        let state = app.summary.state(month: month)
                        let challenge = app.hasWatchedReveal(month: month) || state == .completed || state == .archived
                            ? app.revealedChallenge(month: month) : nil
                        MonthStamp(month: month, state: state, symbol: challenge?.symbol,
                                   accent: challenge.map { Color.token($0.accent) } ?? .gold, showsName: false)
                            .frame(width: 58)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            RollingNumber(text: value, font: .numeral(30, weight: .medium))
            Text(label).font(.caption).foregroundStyle(Color.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

/// After 31 December: the year as an archive.
private struct EndedContent: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("2027").capsLabel(.accentText).padding(.top, 16)
            Text("That was the year.")
                .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
            Text(app.summary.monthsCompleted == 0
                 ? "Everything you explored is still here to look back on."
                 : "You made \(app.summary.monthsCompleted) of its months count. They're all here to look back on.")
                .font(.body).foregroundStyle(Color.inkSoft)
            PrimaryButton(title: "Open your Year in Review", systemImage: "arrow.right") {
                app.sheet = .yearInReview
            }
            SparkCard()
            CollectionStrip()
        }
    }
}

/// Before 1 January 2027: a countdown and a taste of what's coming.
/// Nothing done here is recorded as progress.
private struct PrelaunchContent: View {
    @Environment(AppModel.self) private var app
    let days: Int
    @State private var showTutorial = false
    @State private var showFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Opening 1 January").capsLabel(.accentText).padding(.top, 16)
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    RollingNumber(text: "\(days)", font: .numeral(110, weight: .medium))
                    Text(days == 1 ? "day to go" : "days to go")
                        .font(.editorial(.title2)).italic().foregroundStyle(Color.ink)
                        .padding(.bottom, 18)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(days) \(days == 1 ? "day" : "days") until 2027 begins")
                Text("Your twelve challenges are sealed until the year begins. The first opens at midnight on New Year's Day.")
                    .font(.body).foregroundStyle(Color.inkSoft)
            }

            FeatureCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("While you wait").capsLabel(.gold)
                    Text("Have a look around")
                        .font(.editorial(.title2, weight: .medium)).foregroundStyle(Color.cream)
                    Text("Try two of the tools you'll use during the year. These are demonstrations — nothing is recorded until 2027 begins.")
                        .font(.subheadline).foregroundStyle(Color.cream.opacity(0.75))
                    VStack(spacing: 10) {
                        SecondaryButton(title: "Learn Sudoku in a minute", systemImage: "square.grid.3x3") { showTutorial = true }
                        SecondaryButton(title: "Try a one-minute focus", systemImage: "scope") { showFocus = true }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Twelve months, sealed")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(1...12, id: \.self) { month in
                        MonthStamp(month: month, state: .sealed, symbol: nil, accent: .gold)
                    }
                }
            }
        }
        .sheet(isPresented: $showTutorial) {
            NavigationStack {
                SudokuTutorial(isDemo: true) { showTutorial = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showTutorial = false } }
                    }
            }
        }
        .sheet(isPresented: $showFocus) {
            DemoFocusView { showFocus = false }
        }
    }
}

/// A one-minute, unrecorded taste of the focus timer.
private struct DemoFocusView: View {
    let close: () -> Void
    @State private var start: Date?
    private let length: Double = 60

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let elapsed = start.map { min(length, context.date.timeIntervalSince($0)) } ?? 0
                let finished = elapsed >= length
                VStack(spacing: 28) {
                    Spacer()
                    ZStack {
                        ProgressRing(fraction: elapsed / length, lineWidth: 10, tint: .terracotta, track: .hairline)
                        Text(ProgressCalculator.clock(length - elapsed))
                            .font(.numeral(64, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Color.ink)
                    }
                    .frame(width: 240, height: 240)
                    Text(finished ? "That's the idea. In November, it's ten minutes." : (start == nil ? "One minute. One thing. Nothing else." : "Stay with it…"))
                        .font(.editorial(.title3)).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                    Text("Demonstration only — nothing is recorded.")
                        .font(.footnote).foregroundStyle(Color.inkSoft)
                    Spacer()
                    if finished || start == nil {
                        PrimaryButton(title: finished ? "Done" : "Start", systemImage: finished ? "checkmark" : "play.fill") {
                            if finished { close() } else { start = Date(); Haptics.thud() }
                        }
                    } else {
                        SecondaryButton(title: "Stop", systemImage: "xmark") { start = nil }
                    }
                }
                .padding(24)
            }
            .paperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) }
            }
        }
    }
}
