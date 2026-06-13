import Foundation
import UserNotifications
import ShopwareAdminAPI

/// Background-refresh sync: refreshes every shop's snapshot and diffs old → new into local
/// notifications (orders + reviews always; low stock + unpaid opt-in). The Apple analogue of the
/// Android `SyncWorker`. Scheduled via `BGAppRefreshTask`; also runnable on demand.
@MainActor
struct SyncService {
    let repo: AppRepository

    /// Refreshes all shops, emitting delta notifications. Returns true if anything refreshed.
    @discardableResult
    func runOnce() async -> Bool {
        let data = repo.data
        guard !data.shops.isEmpty else { return false }
        let notifyLowStock = data.notifyLowStock
        let notifyUnpaid = data.notifyUnpaid

        var didRefresh = false
        for shop in data.shops {
            let old = repo.data.snapshots[shop.id]
            let result = await repo.refresh(shopId: shop.id)
            guard case .success = result, let new = repo.data.snapshots[shop.id] else { continue }
            didRefresh = true
            if let old {
                await notifyDeltas(shop: shop, old: old, new: new,
                                   notifyLowStock: notifyLowStock, notifyUnpaid: notifyUnpaid)
            }
        }
        return didRefresh
    }

    private func notifyDeltas(
        shop: ConnectedShop, old: ShopSnapshot, new: ShopSnapshot,
        notifyLowStock: Bool, notifyUnpaid: Bool
    ) async {
        // New orders since last sync (always).
        let oldOrderIds = Set(old.recentOrders.map(\.id))
        let newOrders = new.recentOrders.filter { !$0.id.isEmpty && !oldOrderIds.contains($0.id) }
        if !newOrders.isEmpty {
            let title = String(localized: "^[\(newOrders.count) new order](inflect: true)")
            let body = newOrders.prefix(3).map { "#\($0.orderNumber) · \($0.customer)" }.joined(separator: "\n")
            await post(shop: shop, kind: "orders", title: "\(shop.name): \(title)", body: body)
        }

        // Reviews waiting (always).
        if new.pendingReviews > old.pendingReviews {
            await post(
                shop: shop, kind: "reviews",
                title: shop.name,
                body: String(localized: "^[\(new.pendingReviews) review](inflect: true) awaiting approval")
            )
        }

        // Newly low stock (opt-in).
        let oldLowIds = Set(old.lowStockItems.map(\.id))
        let newlyLow = new.lowStockItems.filter { !$0.id.isEmpty && !oldLowIds.contains($0.id) }
        if notifyLowStock, !newlyLow.isEmpty {
            await post(
                shop: shop, kind: "lowstock",
                title: String(localized: "Low stock — \(shop.name)"),
                body: newlyLow.prefix(3).map { "\($0.name) · \($0.stock)" }.joined(separator: "\n")
            )
        }

        // Unpaid increased (opt-in).
        if notifyUnpaid, new.unpaidOrders > old.unpaidOrders {
            await post(
                shop: shop, kind: "unpaid",
                title: shop.name,
                body: String(localized: "^[\(new.unpaidOrders) order](inflect: true) unpaid 3+ days")
            )
        }
    }

    private func post(shop: ConnectedShop, kind: String, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["shopId": shop.id]
        // Stable id per (shop, kind) so repeated deltas replace rather than stack.
        let request = UNNotificationRequest(identifier: "\(shop.id)-\(kind)", content: content, trigger: nil)
        try? await center.add(request)
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}
