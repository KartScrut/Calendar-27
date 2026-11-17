import Foundation
import TwelveCore
import UserNotifications

/// Gentle, opt-in local reminders. Nothing is scheduled until the person
/// chooses a reminder type, and every message describes real progress.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?
    private static let prefix = "twelve."
    private static let focusID = "twelve.focus.end"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    func cancelAll() {
        pending?.cancel()
        center.removeAllPendingNotificationRequests()
    }

    /// Rebuilds the schedule from current preferences and progress.
    func reschedule(for app: AppModel) {
        guard !app.isDemo, !app.isInMemory else { return }
        let plan = Self.plan(reminders: app.profile.reminders, calendar: app.calendar, now: app.now,
                             challenge: app.currentChallenge.flatMap { app.hasWatchedReveal(month: $0.month) ? $0 : nil },
                             progress: app.currentChallenge.map { app.progress(for: $0) },
                             completed: app.currentMonth.map { app.summary.state(month: $0) == .completed } ?? false)
        pending?.cancel()
        pending = Task { [center] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let existing = await center.pendingNotificationRequests().map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.hasPrefix(Self.prefix) && $0 != Self.focusID })
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.userInfo = ["link": item.link.rawValue]
                let trigger = UNCalendarNotificationTrigger(dateMatching: item.components, repeats: item.repeats)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }

    struct Planned: Equatable {
        let id: String
        let title: String
        let body: String
        let components: DateComponents
        let repeats: Bool
        let link: DeepLink
    }

    /// Pure planning, so the wording and timing can be unit-tested.
    static func plan(reminders: ReminderPreferences, calendar: YearCalendar, now: Date,
                     challenge: ChallengeDefinition?, progress: ChallengeProgress?, completed: Bool) -> [Planned] {
        var out: [Planned] = []
        if case .ended = calendar.phase(at: now) { return [] }

        if reminders.dailySpark, calendar.currentMonth(at: now) != nil {
            var c = DateComponents()
            c.hour = reminders.dailyMinutes / 60
            c.minute = reminders.dailyMinutes % 60
            out.append(Planned(id: prefix + "spark", title: "Today's Spark", body: "A small thing worth knowing today.",
                               components: c, repeats: true, link: .spark))
        }

        if reminders.monthlyReveal {
            for month in 1...12 where calendar.revealDate(month: month) > now {
                var c = DateComponents()
                c.timeZone = calendar.timeZone
                c.year = calendar.year; c.month = month; c.day = 1; c.hour = 9; c.minute = 0
                let name = YearCalendar.monthName(month)
                // Month names are public; the challenge itself stays a surprise.
                out.append(Planned(id: prefix + "reveal.\(month)", title: "\(name) has arrived",
                                   body: "Your next challenge is ready.", components: c, repeats: false, link: .challenge))
            }
        }

        if reminders.progress, let challenge, let progress, !completed, !progress.isComplete,
           case .active(let month, let day) = calendar.phase(at: now), month == challenge.month {
            let remindDay = day < 20 ? 20 : (day < 26 ? 26 : nil)
            if let remindDay, remindDay <= calendar.daysIn(month: month) {
                var c = DateComponents()
                c.timeZone = calendar.timeZone
                c.year = calendar.year; c.month = month; c.day = remindDay; c.hour = 18; c.minute = 0
                out.append(Planned(id: prefix + "progress", title: challenge.title,
                                   body: progressLine(challenge: challenge, progress: progress),
                                   components: c, repeats: false, link: .challenge))
            }
        }
        return out
    }

    /// "3 puzzles down. 2 to go." — always the real numbers.
    static func progressLine(challenge: ChallengeDefinition, progress: ChallengeProgress) -> String {
        let done = Int(progress.value.rounded(.down))
        let left = max(1, Int(challenge.target) - done)
        if done <= 0 { return "\(challenge.monthName)'s challenge is here whenever you're ready." }
        return "\(done) \(challenge.unit) down. \(left) to go."
    }

    // MARK: Focus session end

    func scheduleFocusEnd(at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ten minutes, done"
        content.body = "Your focus session is complete."
        content.sound = .default
        content.userInfo = ["link": DeepLink.challenge.rawValue]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.focusID, content: content, trigger: trigger))
    }

    func cancelFocusEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.focusID])
    }
}
