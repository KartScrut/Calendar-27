import AppIntents
import Foundation
import TwelveCore

// Actions offered to Siri and the Shortcuts app. Each simply opens the right
// place in TWELVE; nothing is changed without the person seeing it.

private func requestOpen(_ link: DeepLink) async {
    await MainActor.run {
        NotificationCenter.default.post(name: .deepLinkRequested, object: link.rawValue)
    }
}

struct OpenSparkIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today's Spark"
    static var description = IntentDescription("Opens today's discovery in TWELVE.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await requestOpen(.spark)
        return .result()
    }
}

struct OpenChallengeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Current Challenge"
    static var description = IntentDescription("Opens this month's challenge in TWELVE.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await requestOpen(.challenge)
        return .result()
    }
}

struct StartActivityTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Activity Timer"
    static var description = IntentDescription("Opens the timer for this month's challenge, when it has one.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await requestOpen(.timer)
        return .result()
    }
}

struct OpenYearIntent: AppIntent {
    static var title: LocalizedStringResource = "View My Year"
    static var description = IntentDescription("Opens your 2027 collection in TWELVE.")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await requestOpen(.year)
        return .result()
    }
}

struct TwelveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenSparkIntent(),
                    phrases: ["Show today's Spark in \(.applicationName)", "Open \(.applicationName) Spark"],
                    shortTitle: "Today's Spark", systemImageName: "sparkles")
        AppShortcut(intent: OpenChallengeIntent(),
                    phrases: ["Open my \(.applicationName) challenge", "Show my challenge in \(.applicationName)"],
                    shortTitle: "Current Challenge", systemImageName: "seal")
        AppShortcut(intent: StartActivityTimerIntent(),
                    phrases: ["Start my \(.applicationName) timer", "Start a timer in \(.applicationName)"],
                    shortTitle: "Start Activity Timer", systemImageName: "timer")
        AppShortcut(intent: OpenYearIntent(),
                    phrases: ["Show my year in \(.applicationName)", "Open my \(.applicationName) year"],
                    shortTitle: "View My Year", systemImageName: "calendar")
    }
}
