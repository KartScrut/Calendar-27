import SwiftUI
import TwelveCore

/// The custom 2027 calendar: a month at a time, or all twelve as a collection.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month = 1
    @State private var forward = true
    @State private var selectedDay: String?
    @Namespace private var glass

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("2027").font(.numeral(44, weight: .medium)).foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Picker("View", selection: $app.showYearOverview) {
                            Text("Month").tag(false)
                            Text("Year").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }
                    .padding(.top, 12)

                    if app.showYearOverview {
                        YearOverview { m in
                            forward = m >= month
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                month = m
                                app.showYearOverview = false
                            }
                        }
                        .transition(.opacity)
                    } else {
                        monthHeader
                        MonthGrid(month: month, selectedDay: $selectedDay)
                            .id(month)
                            .pageTurn(forward: forward, reduceMotion: reduceMotion)
                        if let selectedDay {
                            DayActivity(dayKey: selectedDay)
                        }
                        MonthSummaryCard(month: month)
                            .id("summary-\(month)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: month)
                .animation(.easeInOut(duration: 0.25), value: app.showYearOverview)
            }
            .paperScreen()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { month = app.currentMonth ?? (app.phase == .ended ? 12 : 1) }
        }
    }

    private var monthHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(YearCalendar.twoDigit(month)).capsLabel(.accentText)
                Text(YearCalendar.monthName(month))
                    .font(.editorial(.largeTitle, weight: .medium)).italic().foregroundStyle(Color.ink)
                    .contentTransition(.opacity)
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { go(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(month == 1)
                        .accessibilityLabel("Previous month")
                    Button { go(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(month == 12)
                        .accessibilityLabel("Next month")
                }
            }
        }
    }

    private func go(_ delta: Int) {
        let next = min(12, max(1, month + delta))
        guard next != month else { return }
        forward = delta > 0
        selectedDay = nil
        Haptics.select()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { month = next }
    }
}

/// A Monday-first month grid with activity markers.
private struct MonthGrid: View {
    @Environment(AppModel.self) private var app
    let month: Int
    @Binding var selectedDay: String?

    var body: some View {
        let _ = app.revision
        let cal = app.calendar
        let days = cal.daysIn(month: month)
        let blanks = cal.leadingBlanks(month: month)
        let today = app.todayKey
        let active = activeDays()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(YearCalendar.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial).font(.caption2.weight(.bold)).foregroundStyle(Color.inkSoft).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<(blanks + days), id: \.self) { slot in
                    if slot < blanks {
                        Color.clear.frame(height: 46)
                    } else {
                        let day = slot - blanks + 1
                        let key = cal.dayKey(month: month, day: day)
                        let isToday = key == today
                        let hasActivity = active.contains(key)
                        Button {
                            selectedDay = selectedDay == key ? nil : key
                            Haptics.select()
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(day)")
                                    .font(.numeral(19, weight: isToday ? .bold : .regular))
                                    .foregroundStyle(isToday ? Color.cream : Color.ink)
                                // A shape as well as a colour marks active days.
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(isToday ? Color.gold : Color.accentText)
                                    .opacity(hasActivity ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background {
                                if isToday {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.feature)
                                } else if selectedDay == key {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.gold.opacity(0.3))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(day) \(YearCalendar.monthName(month))\(isToday ? ", today" : "")\(hasActivity ? ", has activity" : "")")
                    }
                }
            }
        }
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.hairline))
    }

    private func activeDays() -> Set<String> {
        var set = Set(app.store.entries().map(\.dayKey))
        for s in app.store.sudokuSaves() { if let d = s.solvedDayKey { set.insert(d) } }
        for p in app.store.dayPicks() where p.microDoneAt != nil { set.insert(p.dayKey) }
        for i in app.store.interactions() where i.answeredAt != nil { set.insert(i.seenDayKey) }
        return set
    }
}

/// What happened on a chosen day.
private struct DayActivity: View {
    @Environment(AppModel.self) private var app
    let dayKey: String

    var body: some View {
        let lines = summary()
        PaperCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title)
                if lines.isEmpty {
                    Text("Nothing logged on this day.").font(.subheadline).foregroundStyle(Color.inkSoft)
                }
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "diamond.fill").font(.subheadline).foregroundStyle(Color.ink)
                        .labelStyle(SmallIconLabelStyle())
                }
            }
        }
        .transition(.opacity)
    }

    private var title: String {
        guard let p = YearCalendar.parse(dayKey: dayKey) else { return dayKey }
        return "\(p.day) \(YearCalendar.monthName(p.month))"
    }

    private func summary() -> [String] {
        var out: [String] = []
        let entries = app.store.entries().filter { $0.dayKey == dayKey }
        for (kind, group) in Dictionary(grouping: entries, by: \.kind).sorted(by: { $0.key < $1.key }) {
            let n = group.count
            let total = group.reduce(0) { $0 + $1.amount }
            switch kind {
            case "plank": out.append("Planked for \(ProgressCalculator.clock(total))")
            case "walk": out.append("Walked for \(Int(total / 60)) min")
            case "focus": out.append("\(n) focus \(n == 1 ? "session" : "sessions")")
            case "reading": out.append("Read \(Int(total)) pages")
            case "photo": out.append("\(n) \(n == 1 ? "photo" : "photos") captured")
            case "observation": out.append("Wrote \(n == 1 ? "an observation" : "\(n) observations")")
            case "kindness": out.append("Recorded \(n == 1 ? "an act of kindness" : "\(n) acts of kindness")")
            case "dish": out.append("Made \(group.compactMap(\.title).joined(separator: ", "))")
            case "moment": out.append("Kept \(n == 1 ? "a moment" : "\(n) moments")")
            case "word_learned": out.append("Learned \(n) \(n == 1 ? "word" : "words")")
            case "quiz_pass": out.append("Passed the recall exercise")
            case "creative_stage": out.append("Creative project: \(n) \(n == 1 ? "stage" : "stages")")
            default: break
            }
        }
        let solved = app.store.sudokuSaves().filter { $0.solvedDayKey == dayKey }.count
        if solved > 0 { out.append("Solved \(solved) Sudoku \(solved == 1 ? "puzzle" : "puzzles")") }
        if app.store.dayPicks().contains(where: { $0.dayKey == dayKey && $0.microDoneAt != nil }) { out.append("Did the day's small extra") }
        if app.store.interactions().contains(where: { $0.seenDayKey == dayKey && $0.answeredAt != nil }) { out.append("Explored the day's Spark") }
        return out
    }
}

private struct SmallIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Color.accentText)
            configuration.title
        }
    }
}

/// The state of a month, in words, beneath its grid.
private struct MonthSummaryCard: View {
    @Environment(AppModel.self) private var app
    let month: Int

    var body: some View {
        let state = app.summary.state(month: month)
        let watched = app.hasWatchedReveal(month: month) || state == .completed || state == .archived
        let challenge = watched ? app.revealedChallenge(month: month) : nil
        Button {
            if state != .sealed, state != .beforeJoining {
                Haptics.tap()
                app.sheet = .challenge(month: month)
            }
        } label: {
            PaperCard(padding: 16) {
                HStack(spacing: 16) {
                    MonthStamp(month: month, state: state, symbol: challenge?.symbol,
                               accent: challenge.map { Color.token($0.accent) } ?? .gold, showsName: false)
                        .frame(width: 62)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(state)).capsLabel(state == .completed ? .goldText : .inkSoft)
                        Text(title(state, challenge)).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Text(detail(state, challenge)).font(.footnote).foregroundStyle(Color.inkSoft)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if state != .sealed, state != .beforeJoining {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSoft)
                    }
                }
            }
        }
        .buttonStyle(LiftButtonStyle())
        .disabled(state == .sealed || state == .beforeJoining)
        .accessibilityElement(children: .combine)
    }

    private func headline(_ state: MonthState) -> String {
        switch state {
        case .sealed: return "Sealed"
        case .active: return "This month"
        case .completed: return "Completed"
        case .archived: return "In the archive"
        case .beforeJoining: return "Before you joined"
        }
    }

    private func title(_ state: MonthState, _ challenge: ChallengeDefinition?) -> String {
        if let challenge { return challenge.title }
        switch state {
        case .sealed: return "A challenge is waiting"
        case .active: return "\(YearCalendar.monthName(month)) is ready to open"
        case .beforeJoining: return "\(YearCalendar.monthName(month)) 2027"
        default: return YearCalendar.monthName(month)
        }
    }

    private func detail(_ state: MonthState, _ challenge: ChallengeDefinition?) -> String {
        switch state {
        case .sealed: return "Opens on 1 \(YearCalendar.monthName(month))."
        case .active:
            if let challenge { return ProgressCalculator.label(for: challenge, progress: app.progress(for: challenge)) }
            return "Tap to reveal this month's challenge."
        case .completed:
            if let at = app.store.stamp(month: month)?.completedAt { return "Stamped on \(at.formatted(.dateTime.day().month(.wide)))." }
            return "Stamped."
        case .archived:
            if let challenge { return "Closed at \(ProgressCalculator.label(for: challenge, progress: app.progress(for: challenge))). Still here to look back on." }
            return "This month has closed."
        case .beforeJoining: return "This month passed before your year began. It doesn't count against you."
        }
    }
}

/// All twelve months as a collection of stamps.
struct YearOverview: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelect: (Int) -> Void
    @State private var nudged: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 22) {
                stat("\(app.summary.monthsCompleted)", "completed")
                stat("\(app.summary.currentStreak)", "current streak")
                stat("\(app.summary.bestStreak)", "best streak")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(1...12, id: \.self) { m in
                    let state = app.summary.state(month: m)
                    let watched = app.hasWatchedReveal(month: m) || state == .completed || state == .archived
                    let challenge = watched ? app.revealedChallenge(month: m) : nil
                    Button {
                        if state == .sealed {
                            // Sealed months stay shut: a small shake, nothing revealed.
                            Haptics.warning()
                            nudged = m
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { nudged = nil }
                        } else {
                            Haptics.tap()
                            onSelect(m)
                        }
                    } label: {
                        MonthStamp(month: m, state: state, symbol: challenge?.symbol,
                                   accent: challenge.map { Color.token($0.accent) } ?? .gold)
                            .rotationEffect(.degrees(nudged == m && !reduceMotion ? -3 : 0))
                            .animation(.spring(response: 0.15, dampingFraction: 0.3), value: nudged)
                    }
                    .buttonStyle(LiftButtonStyle())
                    .accessibilityHint(state == .sealed ? "Sealed until 1 \(YearCalendar.monthName(m))" : "Shows \(YearCalendar.monthName(m))")
                }
            }
            Text("Each finished month becomes a stamp. Months ahead stay sealed until they begin.")
                .font(.footnote).foregroundStyle(Color.inkSoft)
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
