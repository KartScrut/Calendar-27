import ActivityKit
import Foundation
import TwelveCore

/// What the Lock Screen and Dynamic Island show during a timed session.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// While running: a real-time instant such that `now - anchor` is the
        /// active time so far. The system counts up from it on its own.
        var anchor: Date
        /// Non-nil while paused: the frozen active time, in seconds.
        var pausedElapsed: Double?
        /// For countdown sessions (focus): total length in seconds.
        var goalSeconds: Double?
    }

    var title: String
    var kindRaw: String
}

/// Keeps Live Activities in step with the stored timer session.
enum TimerActivityBridge {
    static func state(for session: TimerSession) -> TimerActivityAttributes.ContentState {
        let elapsed = session.elapsed(at: AppClock.now)
        return .init(anchor: Date().addingTimeInterval(-elapsed),
                     pausedElapsed: session.isRunning ? nil : elapsed,
                     goalSeconds: session.kind == .focus ? TimerKind.focus.maximumSeconds : nil)
    }

    static func staleDate(for session: TimerSession) -> Date? {
        guard session.isRunning else { return nil }
        let remaining = session.kind.maximumSeconds - session.elapsed(at: AppClock.now)
        return Date().addingTimeInterval(max(1, remaining))
    }

    static func start(_ session: TimerSession, title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TimerActivityAttributes(title: title, kindRaw: session.kind.rawValue)
        let content = ActivityContent(state: state(for: session), staleDate: staleDate(for: session))
        _ = try? Activity<TimerActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
    }

    static func update(_ session: TimerSession) async {
        let content = ActivityContent(state: state(for: session), staleDate: staleDate(for: session))
        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.update(content)
        }
    }

    static func endAll() async {
        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Pause or resume from a Live Activity button. Works on the stored
    /// session, so it is correct even if the app's screens are not loaded.
    static func toggle() async {
        guard var session = TimerStore.load(), !session.isFinished else {
            await endAll()
            return
        }
        let now = AppClock.now
        if session.isRunning { session.pause(at: now) } else { session.resume(at: now) }
        TimerStore.save(session)
        await update(session)
        NotificationCenter.default.post(name: .timerStoreChanged, object: nil)
    }
}
