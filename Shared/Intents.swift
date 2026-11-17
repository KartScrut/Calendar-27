import AppIntents
import Foundation
import TwelveCore
import WidgetKit

/// Pause/resume button on the Live Activity.
struct TimerToggleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Timer"
    static var description = IntentDescription("Pauses or resumes the active TWELVE session.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await TimerActivityBridge.toggle()
        return .result()
    }
}

/// Marks today's small optional activity as done, straight from the widget.
/// It only records the tap; the app turns it into points the next time it opens.
struct CompleteMicroIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Today's Small Challenge"
    static var description = IntentDescription("Marks today's optional small challenge as done.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Day") var dayKey: String
    @Parameter(title: "Challenge") var microID: String

    init() {}

    init(dayKey: String, microID: String) {
        self.dayKey = dayKey
        self.microID = microID
    }

    func perform() async throws -> some IntentResult {
        MicroInbox.record(dayKey: dayKey, microID: microID)
        var snapshot = WidgetSnapshot.load()
        // Only today's activity can be completed, and only once.
        if snapshot.microDayKey == dayKey, snapshot.microID == microID {
            snapshot.microDoneDayKey = dayKey
            snapshot.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Taps made in the widget, waiting for the app to pick them up.
enum MicroInbox {
    static func record(dayKey: String, microID: String) {
        var pending = load()
        pending[dayKey] = microID
        AppGroup.defaults.set(pending, forKey: AppGroup.pendingMicroKey)
    }

    static func load() -> [String: String] {
        AppGroup.defaults.dictionary(forKey: AppGroup.pendingMicroKey) as? [String: String] ?? [:]
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: AppGroup.pendingMicroKey)
    }
}
