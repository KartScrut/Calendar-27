import SwiftUI
import TwelveCore
import WidgetKit

/// Compact Lock Screen accessories. The system draws these in its own
/// monochrome style, so they rely on shape and weight, never colour.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.lockWidgetKind, provider: CalendarProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Year progress")
        .description("Months completed in 2027, at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        let count = entry.snapshot.completedCount
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(count), in: 0...12) {
                Text("2027")
            } currentValueLabel: {
                HStack(spacing: 1) {
                    Text("\(count)").font(.system(size: 20, weight: .semibold, design: .rounded))
                    if count > 0 { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(DeepLink.year.url)
            .accessibilityLabel("\(count) of 12 months complete")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.shortWeekday) \(entry.day)")
                    .font(.system(size: 17, weight: .bold, design: .rounded)).textCase(.uppercase)
                    .widgetAccentable()
                HStack(spacing: 4) {
                    Text(entry.snapshot.completeLabel).font(.system(size: 13, weight: .medium))
                    if count > 0 { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                }
                Gauge(value: Double(count), in: 0...12) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.year.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.weekday) \(entry.day). \(entry.snapshot.completeLabel)")
        default:
            Text(count > 0 ? "2027 · \(count)/12 ✓" : "2027 · \(count)/12")
                .widgetURL(DeepLink.year.url)
                .accessibilityLabel("2027, \(count) of 12 months complete")
        }
    }
}
