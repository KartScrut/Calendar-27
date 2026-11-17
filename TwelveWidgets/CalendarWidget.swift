import AppIntents
import SwiftUI
import TwelveCore
import WidgetKit

/// One moment on a widget's timeline: the date to show, and the app's latest snapshot.
struct CalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    /// The device's own calendar decides the date on a widget.
    var day: Int { Calendar.current.component(.day, from: date) }
    var weekday: String { date.formatted(.dateTime.weekday(.wide)) }
    var shortWeekday: String { date.formatted(.dateTime.weekday(.abbreviated)) }
    var month: String { date.formatted(.dateTime.month(.wide)) }
    var year: Int { Calendar.current.component(.year, from: date) }

    /// The app's day key for this entry, used to check today's small challenge.
    var dayKey: String {
        let tz = TimeZone(identifier: snapshot.timeZoneID) ?? .current
        return YearCalendar(year: snapshot.year, timeZone: tz).dayKey(for: date)
    }

    /// Challenge details only while they belong to the month being shown, so
    /// a widget that hasn't been refreshed can't show last month's card.
    var challengeIsCurrent: Bool { snapshot.challengeIsCurrent(at: date) }
    var microAvailable: Bool { snapshot.microDayKey == dayKey && snapshot.microID != nil }
    var microDone: Bool { snapshot.microDoneDayKey == dayKey }
}

/// Supplies entries at each midnight. Widgets can't tick every second, and
/// don't need to: the date changes once a day and progress changes only when
/// the app says so (it reloads the timeline itself).
struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(CalendarEntry(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let now = Date()
        var entries = [CalendarEntry(date: now, snapshot: snapshot)]
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<3 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
            entries.append(CalendarEntry(date: next, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.widgetKind, provider: CalendarProvider()) { entry in
            CalendarWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaper() }
        }
        .configurationDisplayName("2027")
        .description("The date, beautifully set, with your year's progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The signature walnut surface with a hint of paper grain.
struct WidgetPaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x533F34), Color.walnut, Color.espresso], startPoint: .topLeading, endPoint: .bottomTrailing)
            PaperGrain(opacity: 0.07, seed: 2027)
        }
    }
}

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallCalendar(entry: entry).widgetURL(DeepLink.today.url)
        case .systemMedium: MediumCalendar(entry: entry).widgetURL(DeepLink.challenge.url)
        default: LargeCalendar(entry: entry)
        }
    }
}

/// "02 / 12 ✓"
private struct CountLine: View {
    let snapshot: WidgetSnapshot
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 5) {
            Text(snapshot.countLabel)
                .font(.system(size: size, weight: .semibold, design: .serif))
                .foregroundStyle(Color.cream)
            if snapshot.completedCount > 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.75, weight: .bold))
                    .foregroundStyle(Color.gold)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.completedCount) of 12 months complete")
    }
}

/// A thin ornamental rule with a small diamond: a printer's flourish.
private struct Ornament: View {
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.gold.opacity(0.7)).frame(height: 1)
            Image(systemName: "diamond.fill").font(.system(size: 5)).foregroundStyle(Color.gold)
            Rectangle().fill(Color.gold.opacity(0.7)).frame(height: 1)
        }
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

private struct SmallCalendar: View {
    let entry: CalendarEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(entry.day)")
                .font(.system(size: 64, weight: .medium, design: .serif))
                .foregroundStyle(Color.cream)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, -8)
            Text(entry.weekday)
                .font(.system(size: 11, weight: .bold)).tracking(1.6).textCase(.uppercase)
                .foregroundStyle(Color.gold)
                .widgetAccentable()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(entry.month)
                .font(.system(size: 11, weight: .semibold)).tracking(1.6).textCase(.uppercase)
                .foregroundStyle(Color.cream.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Ornament().frame(width: 54)
            Spacer(minLength: 4)
            CountLine(snapshot: entry.snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

private struct MediumCalendar: View {
    let entry: CalendarEntry
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(entry.year))
                    .font(.system(size: 10, weight: .bold)).tracking(2)
                    .foregroundStyle(Color.cream.opacity(0.6))
                Text("\(entry.day)")
                    .font(.system(size: 76, weight: .medium, design: .serif))
                    .foregroundStyle(Color.cream)
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .padding(.vertical, -8)
                Text(entry.weekday)
                    .font(.system(size: 11, weight: .bold)).tracking(1.6).textCase(.uppercase)
                    .foregroundStyle(Color.gold).widgetAccentable()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(entry.month)
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6).textCase(.uppercase)
                    .foregroundStyle(Color.cream.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ZStack {
                    TwelveDots(completed: Set(entry.snapshot.completedMonths),
                               current: entry.challengeIsCurrent ? entry.snapshot.challengeMonth : nil)
                        .widgetAccentable()
                    VStack(spacing: -2) {
                        Text("\(entry.snapshot.completedCount)")
                            .font(.system(size: 30, weight: .medium, design: .serif)).foregroundStyle(Color.cream)
                        Text("of 12").font(.system(size: 9, weight: .semibold)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(Color.cream.opacity(0.65))
                    }
                }
                .frame(width: 88, height: 88)
                Text(statusLine)
                    .font(.system(size: 10, weight: .medium, design: .serif)).italic()
                    .foregroundStyle(Color.cream.opacity(0.8))
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(width: 118)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        let s = entry.snapshot
        guard s.onboarded else { return "Make the year count" }
        if entry.challengeIsCurrent {
            if s.challengeComplete { return "This month: complete" }
            return s.challengeProgressLabel ?? s.challengeTitle ?? "Make the year count"
        }
        return "Make the year count"
    }
}

private struct LargeCalendar: View {
    let entry: CalendarEntry
    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 10) {
            Link(destination: DeepLink.today.url) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text("\(entry.day)")
                        .font(.system(size: 78, weight: .medium, design: .serif))
                        .foregroundStyle(Color.cream).minimumScaleFactor(0.6).lineLimit(1)
                        .padding(.vertical, -10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.weekday)
                            .font(.system(size: 12, weight: .bold)).tracking(1.6).textCase(.uppercase)
                            .foregroundStyle(Color.gold).widgetAccentable()
                        Text("\(entry.month) \(String(entry.year))")
                            .font(.system(size: 12, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                            .foregroundStyle(Color.cream.opacity(0.75))
                    }
                    .padding(.bottom, 10)
                    Spacer(minLength: 0)
                    CountLine(snapshot: s, size: 15).padding(.bottom, 10)
                }
            }

            // The twelve-month collection.
            Link(destination: DeepLink.year.url) {
                HStack(spacing: 5) {
                    ForEach(1...12, id: \.self) { month in
                        let done = s.completedMonths.contains(month)
                        let current = entry.challengeIsCurrent && s.challengeMonth == month
                        VStack(spacing: 3) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(done ? Color.gold : Color.cream.opacity(current ? 0.3 : 0.1))
                                    .widgetAccentable(done)
                                if done {
                                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.espresso)
                                }
                            }
                            .frame(height: 24)
                            Text(YearCalendar.twoDigit(month))
                                .font(.system(size: 8, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.cream.opacity(current ? 1 : 0.55))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(s.completeLabel)
            }

            Ornament()

            // Current challenge.
            Link(destination: DeepLink.challenge.url) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("This month").font(.system(size: 9, weight: .bold)).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(Color.gold).widgetAccentable()
                    Text(challengeTitle)
                        .font(.system(size: 17, weight: .medium, design: .serif)).foregroundStyle(Color.cream).lineLimit(1)
                    if entry.challengeIsCurrent, s.onboarded {
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.cream.opacity(0.18))
                                    Capsule().fill(Color.gold)
                                        .frame(width: max(4, geo.size.width * min(1, max(0, s.challengeComplete ? 1 : s.challengeFraction))))
                                        .widgetAccentable()
                                }
                            }
                            .frame(height: 4)
                            Text(s.challengeComplete ? "Complete" : (s.challengeProgressLabel ?? ""))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.cream.opacity(0.8))
                                .lineLimit(1).fixedSize()
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Today's Spark and the small optional activity.
            if let headline = s.sparkHeadline, s.onboarded {
                Link(destination: DeepLink.spark.url) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today's Spark").font(.system(size: 9, weight: .bold)).tracking(1.5).textCase(.uppercase)
                            .foregroundStyle(Color.gold).widgetAccentable()
                        Text(headline).font(.system(size: 14, weight: .regular, design: .serif)).italic()
                            .foregroundStyle(Color.cream).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if entry.microAvailable, let id = s.microID, let title = s.microTitle {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.cream.opacity(0.85)).lineLimit(1)
                    Spacer(minLength: 4)
                    if entry.microDone {
                        Label("Done", systemImage: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.gold)
                    } else {
                        Button(intent: CompleteMicroIntent(dayKey: entry.dayKey, microID: id)) {
                            Text("Done").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.mini)
                        .tint(.terracotta)
                        .accessibilityLabel("Mark today's small challenge done")
                    }
                }
            }
        }
    }

    private var challengeTitle: String {
        let s = entry.snapshot
        guard s.onboarded else { return "Open TWELVE to begin" }
        if entry.challengeIsCurrent, let t = s.challengeTitle { return t }
        return "Open TWELVE to see what's new"
    }
}
