import Foundation
import Observation
import UserNotifications
import ShopwareAdminAPI

enum SyncState: Equatable, Sendable {
    case idle
    case syncing
    case error(String)
}

/// App-wide view model: owns the `AppRepository`, exposes its observable `AppData`, and tracks
/// per-shop sync state. The Apple analogue of the Android `AppViewModel`.
@MainActor
@Observable
final class AppViewModel {
    let repo: AppRepository
    private(set) var sync: [String: SyncState] = [:]
    /// false until the persisted store has loaded on first launch.
    private(set) var loaded = false
    /// Set when a local notification is tapped; consumed by the UI to select the shop and open the
    /// order. `orderId` nil = just switch to the shop.
    var pendingDeepLink: (shopId: String, orderId: String?)?

    init(repo: AppRepository? = nil) {
        self.repo = repo ?? AppRepository()
    }

    var data: AppData { repo.data }

    func bootstrap() async {
        await repo.bootstrap()
        loaded = true
    }

    var selectedShop: ConnectedShop? {
        data.shops.first { $0.id == data.selectedShopId } ?? data.shops.first
    }

    func shop(_ id: String) -> ConnectedShop? { data.shops.first { $0.id == id } }

    func snapshot(_ shopId: String) -> ShopSnapshot? { data.snapshots[shopId] }

    func syncState(_ shopId: String) -> SyncState { sync[shopId] ?? .idle }

    private func errorMessage(_ error: Error) -> String {
        if case ApiError.authExpired = error {
            return String(localized: "auth.session_expired", defaultValue: "Session expired — sign in again")
        }
        return (error as? ApiError)?.message
            ?? error.localizedDescription
    }

    func refresh(_ shopId: String) {
        if sync[shopId] == .syncing { return }
        sync[shopId] = .syncing
        Task {
            let result = await repo.refresh(shopId: shopId)
            switch result {
            case .success: sync[shopId] = .idle
            case let .failure(error): sync[shopId] = .error(errorMessage(error))
            }
        }
    }

    func refreshIfStale(_ shop: ConnectedShop, maxAgeMs: Int64 = 5 * 60_000) {
        let snap = data.snapshots[shop.id]
        if snap == nil || Date().epochMs - (snap?.lastSyncEpochMs ?? 0) > maxAgeMs {
            refresh(shop.id)
        }
    }

    func languagesFor(_ shop: ConnectedShop) async throws -> [LanguageOption] {
        try await repo.languagesFor(shop)
    }

    func setShopLanguage(shopId: String, language: LanguageOption?) {
        sync[shopId] = .syncing
        Task {
            await repo.setShopLanguage(shopId: shopId, language: language)
            sync[shopId] = .idle
        }
    }

    /// Sign-in-again from shop settings; returns nil on success, error text otherwise.
    func reauthenticate(_ shop: ConnectedShop, username: String, password: String) async -> String? {
        do {
            try await repo.reauthenticate(shop: shop, username: username, password: password)
            sync[shop.id] = .idle
            return nil
        } catch {
            return errorMessage(error)
        }
    }

    func setSyncEnabled(_ enabled: Bool) {
        Task {
            await repo.setSyncEnabled(enabled)
            if enabled {
                await SyncService.requestAuthorization()
                BackgroundRefresh.schedule()
            } else {
                BackgroundRefresh.cancel()
            }
        }
    }

    /// Runs a sync immediately (manual "sync now").
    func runSyncNow() {
        Task { await SyncService(repo: repo).runOnce() }
    }

    func setNotifyLowStock(_ enabled: Bool) { Task { await repo.setNotifyLowStock(enabled) } }
    func setNotifyUnpaid(_ enabled: Bool) { Task { await repo.setNotifyUnpaid(enabled) } }

    func selectShop(_ id: String) { Task { await repo.selectShop(id: id) } }
    func removeShop(_ id: String) { Task { await repo.removeShop(id: id) } }

    func updateShopSettings(
        shopId: String, name: String, tintIndex: Int, dailyTarget: Double?, lowStockThreshold: Int
    ) {
        Task {
            await repo.updateShopSettings(
                shopId: shopId, name: name, tintIndex: tintIndex,
                dailyTarget: dailyTarget, lowStockThreshold: lowStockThreshold
            )
        }
    }

    func setProductFields(shopId: String, _ config: ProductFieldConfig) {
        Task { await repo.setProductFields(shopId: shopId, config) }
    }

    // MARK: - Push

    /// Ask for notification permission and register for remote (APNs/FCM) push.
    func enablePush() {
        Task { await pushManager.requestAuthorizationAndRegister() }
    }

    /// Re-push the current FCM token to all shops (e.g. after a shop is added).
    func reregisterPush() { pushManager.reregisterAll() }

    func pushStatus(_ shop: ConnectedShop) async -> PushStatus {
        await repo.pushStatusForShop(shop)
    }

    func registerPush(_ shop: ConnectedShop) async -> PushRegisterResult {
        await repo.registerPushForShop(shop, token: pushManager.fcmToken ?? "", deviceName: PushManager.deviceName)
    }

    func unregisterPush(_ shop: ConnectedShop) async {
        await repo.unregisterPushForShop(shop)
    }

    /// Called when a local notification is tapped: switch to the shop and queue an order deep-link.
    func handleNotification(shopId: String, orderId: String?) {
        guard data.shops.contains(where: { $0.id == shopId }) else { return }
        selectShop(shopId)
        pendingDeepLink = (shopId, orderId)
    }

    /// FCM order pushes carry the shop's APP_URL and the order id; match the connected shop by URL
    /// (normalized) and deep-link to the order.
    func handleRemoteNotification(shopUrl: String?, orderId: String?) {
        guard let shopUrl else { return }
        let target = ShopwareHttp.normalizeBaseUrl(shopUrl)
        guard let shop = data.shops.first(where: { $0.baseUrl == target }) else { return }
        handleNotification(shopId: shop.id, orderId: orderId)
    }
}

/// Routes tapped notification content into the `AppViewModel` for deep-linking. Handles both local
/// notifications (`shopId`) and FCM order pushes (`shopUrl`); also shows FCM pushes while foreground.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppViewModel?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        route(response.notification.request.content.userInfo)
    }

    /// Present order pushes even when the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    private func route(_ info: [AnyHashable: Any]) {
        if let shopId = info["shopId"] as? String {
            model?.handleNotification(shopId: shopId, orderId: info["orderId"] as? String)
        } else if let shopUrl = info["shopUrl"] as? String {
            model?.handleRemoteNotification(shopUrl: shopUrl, orderId: info["orderId"] as? String)
        }
    }
}
