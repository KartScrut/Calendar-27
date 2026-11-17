import SwiftUI
import WidgetKit

@main
struct TwelveWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CalendarWidget()
        LockScreenWidget()
        TimerLiveActivity()
    }
}
