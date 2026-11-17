import Foundation
import Observation
import TwelveCore

/// Runs plank, walk and focus sessions.
///
/// The session lives in shared storage as a list of timestamped events, so it
/// keeps perfect time while the app is in the background, the phone is locked,
/// or the app has been closed and reopened. This object only starts, pauses
/// and finishes it.
@MainActor
@Observable
final class TimerController {
    weak var app: AppModel?
    private(set) var session: TimerSession?
    /// Seconds logged by the most recently finished session (for the summary).
    private(set) var lastLoggedSeconds: Double?
    private(set) var lastWasTooShort = false
    private var observer: NSObjectProtocol?

    init() {
        session = TimerStore.load()
        observer = NotificationCenter.default.addObserver(forName: .timerStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Picks up changes made by Live Activity buttons.
    func reload() {
        session = TimerStore.load()
        rescheduleFocusNotification()
    }

    func elapsed(at now: Date = AppClock.now) -> Double { session?.elapsed(at: now) ?? 0 }

    func isActive(for challenge: ChallengeDefinition) -> Bool { session?.challengeID == challenge.id }

    func start(_ challenge: ChallengeDefinition, kind: TimerKind, variant: String?) {
        guard session == nil, let app, app.isOpen(challenge) else { return }
        let s = TimerSession(challengeID: challenge.id, kind: kind, variant: variant, startedAt: AppClock.now)
        session = s
        lastLoggedSeconds = nil
        lastWasTooShort = false
        TimerStore.save(s)
        TimerActivityBridge.start(s, title: variant ?? kind.displayName)
        rescheduleFocusNotification()
        Haptics.thud()
    }

    func pause() {
        guard var s = session, s.pause(at: AppClock.now) else { return }
        commit(s)
        Haptics.tap()
    }

    func resume() {
        guard var s = session, s.resume(at: AppClock.now) else { return }
        commit(s)
        Haptics.tap()
    }

    private func commit(_ s: TimerSession) {
        session = s
        TimerStore.save(s)
        rescheduleFocusNotification()
        Task { await TimerActivityBridge.update(s) }
    }

    /// Ends the session and logs its active time. Returns the seconds logged,
    /// or nil if it was too short to count. Calling it twice logs once.
    @discardableResult
    func finish() -> Double? {
        guard var s = session else { return nil }
        let now = AppClock.now
        s.finish(at: now)
        let seconds = s.loggableSeconds(at: now)
        var logged: Double?
        if let seconds, let app, let challenge = app.catalog.challenge(id: s.challengeID) {
            let events = try? JSONEncoder().encode(s.events)
            let entry = app.log(challenge, kind: s.kind.rawValue, amount: seconds, variant: s.variant,
                                startedAt: s.startedAt, eventsData: events, id: s.id, at: s.startedAt)
            if entry != nil { logged = seconds }
        }
        clear()
        lastLoggedSeconds = logged
        lastWasTooShort = logged == nil
        if logged != nil { Haptics.success() }
        return logged
    }

    /// Discards the session without logging anything.
    func cancel() {
        clear()
        lastLoggedSeconds = nil
        lastWasTooShort = false
    }

    private func clear() {
        session = nil
        TimerStore.save(nil)
        app?.notifications.cancelFocusEnd()
        Task { await TimerActivityBridge.endAll() }
    }

    /// Finishes a session that has reached its ceiling (a completed focus
    /// session, or a timer left running). Safe to call often.
    func reconcile() {
        guard let s = session, s.reachedLimit(at: AppClock.now) else { return }
        finish()
    }

    private func rescheduleFocusNotification() {
        guard let app else { return }
        app.notifications.cancelFocusEnd()
        guard let s = session, s.kind == .focus,
              let end = s.projectedDate(reaching: TimerKind.focus.maximumSeconds, from: AppClock.now) else { return }
        // Convert from the app clock to real time for the system trigger.
        app.notifications.scheduleFocusEnd(at: end.addingTimeInterval(-AppClock.offset))
    }
}
