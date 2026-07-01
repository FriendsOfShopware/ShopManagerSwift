import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct shopwareApp: App {
    @State private var model = AppViewModel()
    private let notificationDelegate = NotificationDelegate()

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        let model = self.model
        // Configure Firebase (FCM) — no-ops on the placeholder GoogleService-Info.plist.
        pushManager.model = model
        pushManager.configure()
        // Register the background-refresh handler before launch completes (iOS).
        BackgroundRefresh.register(model: model)
        // Route notification taps into the model for deep-linking.
        notificationDelegate.model = model
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .task {
                    if !model.loaded { await model.bootstrap() }
                    if model.data.syncEnabled { BackgroundRefresh.schedule() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}

/// Shared push manager (Firebase/FCM lifecycle). Global so both the App and the platform
/// app-delegate (which the SwiftUI adaptor instantiates) reach the same instance.
@MainActor let pushManager = PushManager()

// MARK: - Platform app delegate (APNs token bridge)

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        MainActor.assumeIsolated { pushManager.setAPNSToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator / no-APNs environments land here; push simply stays inactive.
    }
}
#elseif os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { pushManager.setAPNSToken(deviceToken) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
#endif
