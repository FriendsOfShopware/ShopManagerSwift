import Foundation
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

/// Owns the Firebase/FCM lifecycle on Apple: configures Firebase, bridges the APNs device token to
/// Messaging, receives the rotating FCM registration token, and hands it to the repository to
/// upsert into every shop's `ce_fcn` (reusing the Android gateway contract — FCM delivers via APNs
/// on iOS). No-ops gracefully when Firebase isn't configured (placeholder GoogleService-Info.plist)
/// so the app still builds and runs.
@MainActor
final class PushManager: NSObject {
    weak var model: AppViewModel?

    /// The most recent FCM token, if any (also re-pushed to newly-added shops).
    private(set) var fcmToken: String?

    private var configured = false

    /// Configure Firebase once, at app launch. Safe to call when the plist is a placeholder — the
    /// SDK logs a warning and token retrieval simply never succeeds.
    func configure() {
        #if canImport(FirebaseCore)
        guard !configured else { return }
        // Only configure if a usable options file is present; a placeholder yields nil options.
        if FirebaseApp.app() == nil, let options = FirebaseOptions.defaultOptions(), !options.gcmSenderID.isEmpty, options.gcmSenderID != "000000000000" {
            FirebaseApp.configure()
            configured = true
            Messaging.messaging().delegate = self
        }
        #endif
    }

    /// Requests notification authorization and, if granted, registers for remote (APNs) push.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        #if canImport(UIKit)
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        #endif
    }

    /// Called by the app delegate when APNs returns the device token → hand it to Firebase so it
    /// can mint an FCM token.
    func setAPNSToken(_ deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }

    /// A friendly device name stored alongside the token (shown in the shop's ce_fcn row).
    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Apple device"
        #endif
    }

    /// Re-push the current token to all shops (e.g. after a shop is added).
    func reregisterAll() {
        guard let token = fcmToken, let model else { return }
        Task { await model.repo.registerPushToken(token, deviceName: Self.deviceName) }
    }
}

#if canImport(FirebaseMessaging)
extension PushManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken token: String?) {
        guard let token else { return }
        Task { @MainActor in
            self.fcmToken = token
            await self.model?.repo.registerPushToken(token, deviceName: Self.deviceName)
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit
#endif
