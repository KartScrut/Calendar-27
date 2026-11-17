import AuthenticationServices
import SwiftUI
import TwelveCore

/// Eight short steps that carry someone from "what is this?" to their year.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var forward = true
    @State private var interests: [InterestChoice] = []
    @State private var feeling: YearFeeling?
    @State private var reminders = ReminderPreferences()

    private let lastStep = 7

    /// Follow-up questions exist only for some interests.
    private var needsPersonalising: Bool {
        interests.contains { !(Interests.category($0.category)?.subcategories.isEmpty ?? true) }
    }

    var body: some View {
        ZStack {
            if step == 0 || step == lastStep {
                SkyBackground(style: .vivid).ignoresSafeArea()
            } else {
                PaperBackground()
            }
            if step == 0 {
                FloatingBalloons().ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if step > 0 && step < lastStep {
                    header
                }
                Group {
                    switch step {
                    case 0: WelcomeStep(next: advance)
                    case 1: ConceptStep(next: advance)
                    case 2: InterestsStep(interests: $interests, next: advance)
                    case 3: PersonaliseStep(interests: $interests, next: advance)
                    case 4: FeelingStep(feeling: $feeling, next: advance)
                    case 5: RemindersStep(reminders: $reminders, next: advance)
                    case 6: AccountStep(next: advance)
                    default: YearStartStep(feeling: feeling, finish: finish)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: step)
        .onAppear {
            interests = app.profile.interests
            feeling = app.profile.feeling
            reminders = app.profile.reminders
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                back()
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Back")

            ProgressBar(fraction: Double(step) / Double(lastStep), tint: .pop, height: 8)
                .accessibilityLabel("Step \(step) of \(lastStep - 1)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func advance() {
        Haptics.tap()
        forward = true
        persist()
        var next = step + 1
        if next == 3 && !needsPersonalising { next = 4 }
        step = min(next, lastStep)
    }

    private func back() {
        forward = false
        var previous = step - 1
        if previous == 3 && !needsPersonalising { previous = 2 }
        step = max(previous, 0)
    }

    /// Save choices as we go, so nothing is lost if the app is closed mid-way.
    private func persist() {
        app.updateProfile { p in
            p.interests = interests
            p.feeling = feeling
            p.reminders = reminders
        }
    }

    private func finish() {
        persist()
        Haptics.success()
        app.finishOnboarding()
    }
}

// MARK: 1 · Welcome

private struct WelcomeStep: View {
    let next: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            ZStack {
                TwelveDots(completed: appeared ? Set(1...12) : [], current: nil, on: .lime, off: Color.white.opacity(0.35))
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -40))
                    .animation(reduceMotion ? nil : .spring(response: 1.4, dampingFraction: 0.8), value: appeared)
                Text("2027")
                    .font(.numeral(92, weight: .medium))
                    .foregroundStyle(Color.cloud)
                    .shadow(color: Color.ocean.opacity(0.5), radius: 12, y: 4)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? .easeIn : .spring(response: 0.9, dampingFraction: 0.75).delay(0.15), value: appeared)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 12) {
                Text("A year is a lot of days.")
                    .font(.editorial(.largeTitle, weight: .medium))
                    .foregroundStyle(Color.cloud)
                Text("Let's give a few of them something to remember.")
                    .font(.title3)
                    .foregroundStyle(Color.cloud.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.7).delay(0.5), value: appeared)
            .padding(.horizontal, 28)

            PrimaryButton(title: "Make 2027 count", systemImage: "arrow.right", action: next)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { appeared = true }
    }
}

// MARK: 2 · Concept

private struct ConceptStep: View {
    let next: () -> Void
    @State private var shown = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [(String, String, String, MonthState)] = [
        ("01", "A new challenge arrives every month.", "Sealed until the first day, then yours to open.", .sealed),
        ("02", "Complete it at your own pace.", "A little at a time. Your progress is always saved.", .active),
        ("03", "Collect 12 memories of a year well spent.", "Each finished month becomes a stamp you keep.", .completed),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How it works")
                .font(.editorial(.largeTitle, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(.top, 28)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index < shown {
                        HStack(spacing: 16) {
                            MonthStamp(month: index + 1, state: item.3, symbol: index == 0 ? nil : (index == 1 ? "figure.walk" : "sparkles"),
                                       accent: index == 1 ? .mint : .lime, showsName: false)
                                .frame(width: 66)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.1).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                                Text(item.2).font(.subheadline).foregroundStyle(Color.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.top, 24)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: shown)

            Spacer(minLength: 16)
            PrimaryButton(title: shown < items.count ? "Next" : "Sounds good", systemImage: "arrow.right") {
                if shown < items.count {
                    Haptics.tap()
                    shown += 1
                } else {
                    next()
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: 3 · Interests

struct InterestGrid: View {
    @Binding var interests: [InterestChoice]

    private var selected: Set<String> { Set(interests.map(\.category)) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Interests.all) { category in
                let isOn = selected.contains(category.id)
                let atLimit = interests.count >= Interests.maximumSelection
                Button {
                    toggle(category)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: category.symbol)
                                .font(.title2.weight(.light))
                                .foregroundStyle(isOn ? Color.cloud : Color.accentText)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? Color.lime : Color.hairline)
                        }
                        Text(category.name).font(.headline).foregroundStyle(isOn ? Color.cloud : Color.ink)
                        Text(category.blurb).font(.caption).foregroundStyle(isOn ? Color.cloud.opacity(0.75) : Color.inkSoft)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                    .background(isOn ? Color.feature : Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(isOn ? Color.clear : Color.hairline))
                    .opacity(!isOn && atLimit ? 0.5 : 1)
                }
                .buttonStyle(LiftButtonStyle())
                .accessibilityLabel(category.name)
                .accessibilityHint(category.blurb)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: interests)
    }

    private func toggle(_ category: InterestCategory) {
        if let i = interests.firstIndex(where: { $0.category == category.id }) {
            interests.remove(at: i)
            Haptics.select()
        } else if interests.count < Interests.maximumSelection {
            interests.append(InterestChoice(category: category.id))
            Haptics.select()
        } else {
            Haptics.warning()
        }
    }
}

private struct InterestsStep: View {
    @Binding var interests: [InterestChoice]
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you curious about?")
                        .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose two to four. They shape your daily Spark — you can change them any time.")
                        .font(.subheadline).foregroundStyle(Color.inkSoft)
                    InterestGrid(interests: $interests).padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            PrimaryButton(title: interests.count < Interests.minimumSelection ? "Choose at least two" : "Continue",
                          systemImage: "arrow.right", action: next)
                .disabled(interests.count < Interests.minimumSelection)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: 4 · Personalise

struct SubcategoryPicker: View {
    @Binding var interests: [InterestChoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(interests.indices, id: \.self) { index in
                if let category = Interests.category(interests[index].category), !category.subcategories.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(category.name)
                        Text(category.question ?? "").font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                        FlowChips(options: category.subcategories.map { ($0.id, $0.name) }, selection: interests[index].subcategory) { id in
                            interests[index].subcategory = interests[index].subcategory == id ? nil : id
                            Haptics.select()
                        }
                    }
                }
            }
        }
    }
}

/// Selectable chips that wrap onto as many lines as they need.
struct FlowChips: View {
    let options: [(String, String)]
    let selection: String?
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.0) { option in
                let isOn = selection == option.0
                Button {
                    onTap(option.0)
                } label: {
                    HStack {
                        Text(option.1).font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Color.lime : Color.hairline)
                    }
                    .foregroundStyle(isOn ? Color.cloud : Color.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(isOn ? Color.feature : Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isOn ? Color.clear : Color.hairline))
                }
                .buttonStyle(LiftButtonStyle())
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}

private struct PersonaliseStep: View {
    @Binding var interests: [InterestChoice]
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little more detail")
                        .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Optional — it helps us pick better things for you.")
                        .font(.subheadline).foregroundStyle(Color.inkSoft)
                    SubcategoryPicker(interests: $interests).padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            PrimaryButton(title: "Continue", systemImage: "arrow.right", action: next)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: 5 · Feeling

private struct FeelingStep: View {
    @Binding var feeling: YearFeeling?
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How would you like your year to feel?")
                        .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("This shapes the small daily extras. The twelve monthly challenges are the same for everyone.")
                        .font(.subheadline).foregroundStyle(Color.inkSoft)
                    VStack(spacing: 10) {
                        ForEach(YearFeeling.allCases, id: \.self) { option in
                            let isOn = feeling == option
                            Button {
                                feeling = option
                                Haptics.select()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: option.symbol).font(.title3).frame(width: 30)
                                        .foregroundStyle(isOn ? Color.lime : Color.accentText)
                                    Text(option.title).font(.editorial(.title3, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(isOn ? Color.cloud : Color.ink)
                                .padding(18)
                                .background(isOn ? Color.feature : Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(isOn ? Color.clear : Color.hairline))
                            }
                            .buttonStyle(LiftButtonStyle())
                            .accessibilityAddTraits(isOn ? [.isSelected] : [])
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            PrimaryButton(title: "Continue", systemImage: "arrow.right", action: next)
                .disabled(feeling == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: 6 · Reminders

struct ReminderToggles: View {
    @Binding var reminders: ReminderPreferences

    var body: some View {
        VStack(spacing: 0) {
            row("A daily discovery", "One small thing worth knowing, once a day.", $reminders.dailySpark)
            if reminders.dailySpark {
                DatePicker("Time", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: reminders.dailyMinutes / 60, minute: reminders.dailyMinutes % 60, second: 0, of: Date()) ?? Date()
                }, set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    reminders.dailyMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
                .font(.subheadline)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            Divider().overlay(Color.hairline)
            row("Monthly challenge announcements", "A note on the 1st when a new challenge is ready.", $reminders.monthlyReveal)
            Divider().overlay(Color.hairline)
            row("Occasional progress reminders", "At most two a month, and only with your real progress.", $reminders.progress)
        }
        .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
        .animation(.snappy, value: reminders)
    }

    private func row(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Color.ink)
                Text(detail).font(.caption).foregroundStyle(Color.inkSoft)
            }
        }
        .tint(.pop)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct RemindersStep: View {
    @Environment(AppModel.self) private var app
    @Binding var reminders: ReminderPreferences
    let next: () -> Void
    @State private var denied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Would a gentle nudge help?")
                        .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("No streak alarms, no guilt. Choose what's useful, or nothing at all.")
                        .font(.subheadline).foregroundStyle(Color.inkSoft)
                    ReminderToggles(reminders: $reminders).padding(.top, 16)
                    if denied {
                        InfoBanner(symbol: "bell.slash", text: "Notifications are switched off for TWELVE in Settings. You can turn them on there later.")
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            VStack(spacing: 10) {
                PrimaryButton(title: reminders.anyEnabled ? "Turn on reminders" : "Continue without reminders", systemImage: "arrow.right") {
                    if reminders.anyEnabled {
                        // Ask the system only now that someone has opted in.
                        Task {
                            let granted = await app.notifications.requestAuthorization()
                            if !granted {
                                denied = true
                                reminders = ReminderPreferences()
                            }
                            next()
                        }
                    } else {
                        next()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: 7 · Account

private struct AccountStep: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep your year safe")
                        .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("An account backs up your progress and keeps it in step across your devices. Or start as a guest: everything stays on this iPhone, and you can add an account later without losing anything.")
                        .font(.subheadline).foregroundStyle(Color.inkSoft)
                    SignInPanel(onSignedIn: next)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            Button("Explore as a guest", action: next)
                .font(.headline)
                .foregroundStyle(Color.accentText)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
        }
    }
}

// MARK: 8 · Your year

private struct YearStartStep: View {
    @Environment(AppModel.self) private var app
    let feeling: YearFeeling?
    let finish: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("2027").capsLabel(.lime)
                Text("Your year starts here.")
                    .font(.editorial(.largeTitle, weight: .medium))
                    .foregroundStyle(Color.cloud)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.cloud.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 36)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(1...12, id: \.self) { month in
                    let state = app.summary.state(month: month)
                    MonthStamp(month: month, state: state == .beforeJoining || state == .archived ? .beforeJoining : state,
                               symbol: app.currentMonth == month ? "sparkle" : nil,
                               accent: .lime)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 18)
                        .animation(reduceMotion ? .easeIn : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(month) * 0.045), value: appeared)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)

            Spacer(minLength: 12)
            PrimaryButton(title: "Begin", systemImage: "arrow.right", action: finish)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { appeared = true }
    }

    private var subtitle: String {
        switch app.phase {
        case .prelaunch(let days):
            return "The first challenge opens on 1 January — \(days) \(days == 1 ? "day" : "days") from now. Until then, have a look around."
        case .active(let month, _):
            return "\(YearCalendar.monthName(month)) is open. The months ahead stay sealed until they arrive. " + (feeling?.welcomeLine ?? "")
        case .ended:
            return "2027 has finished, but everything here is still yours to explore."
        }
    }
}
