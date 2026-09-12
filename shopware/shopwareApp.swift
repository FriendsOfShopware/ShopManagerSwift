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
        pushManager.configure()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // Register the BGTask launch handler before launch finishes (iOS requires this early).
        // The handler closure strongly captures the model, so it stays valid; this is safe here.
        BackgroundRefresh.register(model: model)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--navigation-ui-fixtures") {
                NavigationUITestRoot().tint(Theme.accent)
            } else if ProcessInfo.processInfo.arguments.contains("--customer-ui-fixtures") {
                CustomerUITestRoot()
                    .tint(Theme.accent)
            } else if ProcessInfo.processInfo.arguments.contains("--media-ui-fixtures") {
                MediaUITestRoot().tint(Theme.accent)
            } else if ProcessInfo.processInfo.arguments.contains("--promotion-ui-fixtures") {
                PromotionUITestRoot().tint(Theme.accent)
            } else if ProcessInfo.processInfo.arguments.contains("--product-ui-fixtures") {
                ProductUITestRoot().tint(Theme.accent)
            } else if ProcessInfo.processInfo.arguments.contains("--review-ui-fixtures") {
                ReviewUITestRoot().tint(Theme.accent)
            } else if ProcessInfo.processInfo.arguments.contains("--order-ui-fixtures") {
                OrderUITestRoot().tint(Theme.accent)
            } else {
                applicationRoot
            }
            #else
            applicationRoot
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }

    private var applicationRoot: some View {
        RootView()
            .environment(model)
            .tint(Theme.accent)
            .task {
                // Wire the model into the weak-referencing push/notification plumbing using the
                // installed @State model. Doing this in init() assigned a temporary that
                // deallocated right after — leaving these weak refs nil (the compiler warning).
                pushManager.model = model
                notificationDelegate.model = model

                if !model.loaded { await model.bootstrap() }
                if model.data.syncEnabled { BackgroundRefresh.schedule() }
            }
    }
}

/// Shared push manager (native APNs lifecycle). Global so both the App and the platform
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
