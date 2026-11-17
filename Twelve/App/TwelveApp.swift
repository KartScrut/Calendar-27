import SwiftUI
import TwelveCore
import UIKit
import UserNotifications

@main
struct TwelveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(.terracotta)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { app.open(link) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .deepLinkRequested)) { note in
                    if let raw = note.object as? String, let link = DeepLink(rawValue: raw) { app.open(link) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    app.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        app.timer.reload()
                        app.timer.reconcile()
                        app.refresh()
                        app.sync.schedule()
                        if let link = AppDelegate.pendingLink {
                            AppDelegate.pendingLink = nil
                            app.open(link)
                        }
                    } else if phase == .background {
                        app.store.save()
                    }
                }
        }
    }
}

/// Handles Home Screen quick actions and notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// A link that arrived before the interface was ready.
    @MainActor static var pendingLink: DeepLink?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem, let link = DeepLink(shortcutType: item.type) {
            AppDelegate.pendingLink = link
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["link"] as? String
        await MainActor.run {
            if let raw, DeepLink(rawValue: raw) != nil {
                NotificationCenter.default.post(name: .deepLinkRequested, object: raw)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard let link = DeepLink(shortcutType: shortcutItem.type) else { return false }
        await MainActor.run {
            NotificationCenter.default.post(name: .deepLinkRequested, object: link.rawValue)
        }
        return true
    }
}

/// Chooses between onboarding and the main interface, and hosts global sheets.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if app.isOnboarded {
                MainTabs()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: app.isOnboarded)
        .sheet(item: $app.sheet) { sheet in
            switch sheet {
            case .challenge(let month): ChallengeScreen(month: month)
            case .spark: SparkScreen()
            case .account: AccountSheet()
            case .yearInReview: YearInReviewScreen()
            }
        }
        .fullScreenCover(item: $app.celebration) { challenge in
            CelebrationScreen(challenge: challenge)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab("Today", systemImage: "sun.max", value: AppModel.Tab.today) {
                TodayScreen()
            }
            Tab("Calendar", systemImage: "calendar", value: AppModel.Tab.calendar) {
                CalendarScreen()
            }
            Tab("Collection", systemImage: "seal", value: AppModel.Tab.collection) {
                CollectionScreen()
            }
            Tab("Profile", systemImage: "person", value: AppModel.Tab.profile) {
                ProfileScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
