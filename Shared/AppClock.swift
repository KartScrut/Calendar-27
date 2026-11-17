import Foundation
import TwelveCore

/// The app's notion of "now". In release builds this is always the real time.
/// Debug builds can shift it (Profile → Developer) to preview any day of 2027;
/// while shifted, the app uses a separate demo database so nothing pretend can
/// ever count toward the real year.
enum AppClock {
    static let offsetKey = "debug.clock.offset"

    static var offset: TimeInterval {
        #if DEBUG
        return AppGroup.defaults.double(forKey: offsetKey)
        #else
        return 0
        #endif
    }

    static var now: Date { Date().addingTimeInterval(offset) }
    static var isSimulated: Bool { offset != 0 }

    #if DEBUG
    static func simulate(_ date: Date?) {
        if let date {
            AppGroup.defaults.set(date.timeIntervalSince(Date()), forKey: offsetKey)
        } else {
            AppGroup.defaults.removeObject(forKey: offsetKey)
        }
    }
    #endif
}

extension Notification.Name {
    static let timerStoreChanged = Notification.Name("twelve.timerStoreChanged")
    static let deepLinkRequested = Notification.Name("twelve.deepLinkRequested")
}
