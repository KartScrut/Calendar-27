import SwiftUI
import TwelveCore

/// The timer used for March's planks, September's walks and November's
/// focus sessions. A quiet screen with one very large number.
struct TimerModule: View {
    @Environment(AppModel.self) private var app
    let challenge: ChallengeDefinition

    @State private var confirmCancel = false
    @State private var deleting: ActivityEntry?
    @State private var lastMinute = 0
    @State private var importing = false
    @State private var importNote: String?
    @State private var intention = ""

    private var kind: TimerKind {
        if challenge.module == .focus { return .focus }
        return challenge.entryKind == "walk" ? .walk : .plank
    }

    private var variant: String? {
        guard app.profile.useAccessibleVariant, let alt = challenge.accessibleAlternative else { return nil }
        return alt.title
    }

    var body: some View {
        let _ = app.revision
        let open = app.isOpen(challenge)
        let session = app.timer.session.flatMap { $0.challengeID == challenge.id ? $0 : nil }
        let entries = app.entries(for: challenge).reversed()
        let loggedSeconds = entries.reduce(0) { $0 + $1.amount }

        ScrollView {
            VStack(spacing: 22) {
                TimelineView(.periodic(from: .now, by: session?.isRunning == true ? 0.25 : 1)) { _ in
                    clockFace(session: session, loggedSeconds: loggedSeconds)
                }

                if let name = variant {
                    Tag(text: name, systemImage: "figure.seated.side.left", tint: .sageText)
                }

                if open {
                    controls(session: session)
                } else if session == nil {
                    InfoBanner(symbol: "archivebox", text: "This month has closed. Your sessions are kept below.")
                }

                if let note = finishNote, session == nil {
                    InfoBanner(symbol: app.timer.lastWasTooShort ? "info.circle" : "checkmark.circle", text: note)
                }

                if kind == .focus, session == nil, open {
                    TextField("What will you give your attention to? (optional)", text: $intention)
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                }

                guidance

                if kind == .walk, open { healthSection }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(entries.isEmpty ? "Sessions" : "Sessions · \(entries.count)")
                    if entries.isEmpty {
                        EmptyNote(symbol: "timer", title: "No sessions yet",
                                  message: open ? "Each finished session is added here and to your monthly total." : "Nothing was logged this month.")
                    }
                    ForEach(Array(entries), id: \.id) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
                                Text((entry.variant ?? kind.displayName) + " · " + entry.date.formatted(.dateTime.hour().minute()))
                                    .font(.caption).foregroundStyle(Color.inkSoft)
                            }
                            Spacer()
                            Text(ProgressCalculator.clock(entry.amount))
                                .font(.numeral(22, weight: .medium)).monospacedDigit().foregroundStyle(Color.ink)
                            Button {
                                deleting = entry
                            } label: {
                                Image(systemName: "trash").font(.footnote).foregroundStyle(Color.inkSoft).frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("Delete session")
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 8)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .task {
            // Keep the session honest while this screen is visible: finish it
            // at its ceiling and mark each full minute with a gentle tap.
            while !Task.isCancelled {
                app.timer.reconcile()
                if let s = app.timer.session, s.isRunning, s.kind != .focus {
                    let minute = Int(s.elapsed(at: AppClock.now)) / 60
                    if minute > lastMinute { Haptics.thud() }
                    lastMinute = minute
                } else {
                    lastMinute = 0
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Cancel this session?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel session", role: .destructive) { app.timer.cancel() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The time on the clock won't be saved.")
        }
        .confirmationDialog("Delete this session?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting { app.remove(d) }
                deleting = nil
            }
        } message: {
            Text("Its time will be removed from your monthly total.")
        }
    }

    // MARK: Clock

    @ViewBuilder
    private func clockFace(session: TimerSession?, loggedSeconds: Double) -> some View {
        let now = AppClock.now
        let current = session?.elapsed(at: now) ?? 0
        let goalSeconds = kind == .focus ? TimerKind.focus.maximumSeconds : challenge.target * 60
        let fraction: Double = kind == .focus
            ? (session == nil ? 0 : current / goalSeconds)
            : min(1, (loggedSeconds + current) / goalSeconds)
        let big: String = kind == .focus
            ? ProgressCalculator.clock(max(0, goalSeconds - current).rounded(.up))
            : ProgressCalculator.clock(loggedSeconds + current)
        let sessionsDone = Int(app.progress(for: challenge).value)

        ZStack {
            ProgressRing(fraction: fraction, lineWidth: 12, tint: .terracotta, track: .hairline)
            VStack(spacing: 4) {
                Text(kind == .focus ? (session == nil ? "Ten minutes" : (session?.isPaused == true ? "Paused" : "Stay with it"))
                                    : (session == nil ? "This month" : (session?.isPaused == true ? "Paused" : kind.displayName)))
                    .capsLabel(.accentText)
                Text(big)
                    .font(.numeral(68, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(kind == .focus ? "Session \(min(sessionsDone + 1, Int(challenge.target))) of \(Int(challenge.target))"
                                    : "/ \(ProgressCalculator.clock(goalSeconds))")
                    .font(.editorial(.title3)).foregroundStyle(Color.inkSoft)
                if session != nil, kind != .focus {
                    Text("This session \(ProgressCalculator.clock(current))")
                        .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Color.accentText)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 30)
        }
        .frame(width: 290, height: 290)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .focus
                            ? "Focus timer, \(ProgressCalculator.clock(max(0, goalSeconds - current))) remaining"
                            : "\(ProgressCalculator.clock(loggedSeconds + current)) of \(ProgressCalculator.clock(goalSeconds)) this month")
    }

    @ViewBuilder
    private func controls(session: TimerSession?) -> some View {
        if let session {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if session.isPaused {
                        PrimaryButton(title: "Resume", systemImage: "play.fill") { app.timer.resume() }
                    } else {
                        PrimaryButton(title: "Pause", systemImage: "pause.fill", tint: .walnut) { app.timer.pause() }
                    }
                    if kind != .focus {
                        PrimaryButton(title: "Finish", systemImage: "checkmark") { app.timer.finish() }
                    }
                }
                Button("Cancel session") { confirmCancel = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.inkSoft)
                    .frame(minHeight: 44)
            }
        } else if app.timer.session != nil {
            InfoBanner(symbol: "timer", text: "Another session is already running. Finish it first.")
        } else {
            PrimaryButton(title: kind == .focus ? "Start ten minutes" : "Start", systemImage: "play.fill") {
                app.timer.start(challenge, kind: kind, variant: variant)
            }
        }
    }

    private var finishNote: String? {
        if let seconds = app.timer.lastLoggedSeconds {
            return kind == .focus ? "Session complete. Ten focused minutes, logged." : "Logged \(ProgressCalculator.clock(seconds)). Nicely done."
        }
        if app.timer.lastWasTooShort {
            return kind == .focus ? "A focus session counts once it reaches the full ten minutes. Try again whenever you like."
                                  : "That one was too short to log. No harm done."
        }
        return nil
    }

    private var guidance: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Good to know")
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Color.accentText)
                        Text(tip).font(.subheadline).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let note = challenge.safetyNote {
                    Text(note).font(.footnote).foregroundStyle(Color.inkSoft).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tips: [String] {
        switch kind {
        case .plank:
            return ["You don't need to keep this screen open. Lock your phone and the clock keeps perfect time.",
                    "Paused time is never counted. Rest as long as you need.",
                    "We take your word for it — the phone can't see your form, and doesn't try to."]
        case .walk:
            return ["Put the phone in your pocket; the timer runs while it's locked.",
                    "No location is recorded, ever. Only the minutes.",
                    "Short walks count. They add up across the month."]
        case .focus:
            return ["Choose one thing. Put the phone face down.",
                    "You'll get a notification when the ten minutes are up, if notifications are on.",
                    "A session counts when it reaches the full ten minutes."]
        }
    }

    // MARK: Health

    private var healthSection: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Apple Health · optional")
                Text(app.profile.healthEnabled
                     ? "Bring in walking workouts recorded this month, for example by a watch. Each walk is added once."
                     : "If you record walks with a watch or another app, TWELVE can read those walking workouts — and nothing else — with your permission.")
                    .font(.subheadline).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                if !HealthService.shared.isAvailable {
                    Text("Health isn't available on this device. The timer works everywhere.")
                        .font(.footnote).foregroundStyle(Color.inkSoft)
                } else if app.profile.healthEnabled {
                    SecondaryButton(title: importing ? "Looking…" : "Import this month's walks", systemImage: "arrow.down.heart") {
                        importWalks()
                    }
                    .disabled(importing)
                } else {
                    SecondaryButton(title: "Connect Health", systemImage: "heart") {
                        Task {
                            if await HealthService.shared.requestAccess() {
                                app.updateProfile { $0.healthEnabled = true }
                            }
                        }
                    }
                }
                if let importNote { Text(importNote).font(.footnote).foregroundStyle(Color.sageText) }
            }
        }
    }

    private func importWalks() {
        importing = true
        importNote = nil
        Task {
            let start = app.calendar.revealDate(month: challenge.month)
            let walks = await HealthService.shared.walks(from: start, to: app.now)
            var added = 0
            for walk in walks {
                // The workout's own identifier is the entry id, so a walk can
                // never be imported twice.
                let seconds = min(walk.seconds.rounded(.down), TimerKind.walk.maximumSeconds)
                guard seconds >= TimerKind.walk.minimumSeconds else { continue }
                if app.log(challenge, kind: "walk", amount: seconds, variant: "Apple Health", startedAt: walk.start,
                           id: walk.id, at: walk.start, allowBackdated: true) != nil {
                    added += 1
                }
            }
            importNote = added == 0 ? "No new walks to add." : "Added \(added) \(added == 1 ? "walk" : "walks") from Health."
            importing = false
        }
    }
}
