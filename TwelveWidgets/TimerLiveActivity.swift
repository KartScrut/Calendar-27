import ActivityKit
import AppIntents
import SwiftUI
import TwelveCore
import WidgetKit

/// The Lock Screen banner and Dynamic Island for a running plank, walk or
/// focus session. The system counts the time itself from the anchor date, so
/// it stays accurate without the app running.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.system(size: 11, weight: .bold)).tracking(1.5).textCase(.uppercase)
                        .foregroundStyle(Color.lime)
                    TimerText(state: context.state)
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.cloud)
                    Text(context.state.pausedElapsed == nil ? (context.state.goalSeconds == nil ? "In progress" : "Stay with it") : "Paused")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.cloud.opacity(0.7))
                }
                Spacer()
                ToggleButton(paused: context.state.pausedElapsed != nil, large: true)
            }
            .padding(16)
            .activityBackgroundTint(Color.ocean)
            .activitySystemActionForegroundColor(Color.cloud)
            .widgetURL(DeepLink.timer.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: symbol(context.attributes.kindRaw))
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.lime)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.pausedElapsed == nil ? "Running" : "Paused")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    TimerText(state: context.state)
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ToggleButton(paused: context.state.pausedElapsed != nil, large: false)
                }
            } compactLeading: {
                Image(systemName: symbol(context.attributes.kindRaw)).foregroundStyle(Color.lime)
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: symbol(context.attributes.kindRaw)).foregroundStyle(Color.lime)
            }
            .widgetURL(DeepLink.timer.url)
        }
    }

    private func symbol(_ kind: String) -> String {
        switch kind {
        case "walk": return "figure.walk"
        case "focus": return "scope"
        default: return "timer"
        }
    }
}

/// Counts up for planks and walks, down for focus; frozen while paused.
private struct TimerText: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.pausedElapsed {
                Text(ProgressCalculator.clock(state.goalSeconds.map { max(0, $0 - paused) } ?? paused))
            } else if let goal = state.goalSeconds {
                Text(timerInterval: state.anchor...state.anchor.addingTimeInterval(goal), countsDown: true)
            } else {
                Text(timerInterval: state.anchor...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.leading)
    }
}

private struct ToggleButton: View {
    let paused: Bool
    let large: Bool

    var body: some View {
        Button(intent: TimerToggleIntent()) {
            Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                .font(large ? .subheadline.weight(.semibold) : .footnote.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.pop)
    }
}
