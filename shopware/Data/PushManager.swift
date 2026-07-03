import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Owns the native APNs lifecycle: requests notification authorization, registers for remote push,
/// and hands the APNs device token (as a hex string) straight to the repository to upsert into every
/// shop's `ce_fcn` row. No Firebase — the device token is the token the push gateway sends to.
/// The gateway talks to `api.push.apple.com` directly; the row's `platform` marks it as `apns`.
@MainActor
final class PushManager: NSObject {
    weak var model: AppViewModel?

    /// The most recent APNs device token (hex), if any. Re-pushed to newly-added shops.
    private(set) var apnsToken: String?

    /// The wire value stored in `ce_fcn.platform` so the gateway routes via APNs (not FCM).
    static let platform = "apns"

    /// No-op kept for launch-time symmetry (nothing to configure without Firebase).
    func configure() {}

    /// Requests notification authorization and, if granted, registers for remote (APNs) push.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        registerForRemoteNotifications()
    }

    private func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif canImport(AppKit)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Called by the app delegate when APNs returns the device token. This token IS what we register
    /// with the shop — no second-hop token minting.
    func setAPNSToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        apnsToken = hex
        guard let model else { return }
        Task { await model.repo.registerPushToken(hex, platform: Self.platform, deviceName: Self.deviceName) }
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
        guard let token = apnsToken, let model else { return }
        Task { await model.repo.registerPushToken(token, platform: Self.platform, deviceName: Self.deviceName) }
    }
}
