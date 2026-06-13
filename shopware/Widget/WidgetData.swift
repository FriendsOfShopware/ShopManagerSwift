import Foundation

/// Today widget state, computed off the cached files only.
struct WidgetState: Equatable {
    let shopName: String
    let revenueText: String
    let deltaLabel: String
    let deltaUp: Bool
    /// null when no daily target
    let targetPct: Double?
    let targetText: String?
    let lastSyncMs: Int64
    let tintIndex: Int
}

/// Weekly widget state: the 7-day total + per-day bars (today highlighted).
struct WeeklyWidgetState: Equatable {
    let shopName: String
    let weekTotalText: String
    let deltaLabel: String
    let deltaUp: Bool
    /// each value normalized 0..1 against the week max
    let bars: [Double]
    let todayIndex: Int
    let lastSyncMs: Int64
}

/// The widget runs outside the app process, so it reads the cache directly instead of going
/// through `AppRepository`: `app-data.json` is plain JSON and snapshots are per-shop files. All
/// synchronous. The Apple analogue of the Android `WidgetData`.
enum WidgetData {
    private static let decoder = JSONDecoder()

    static func readSelectedShopSnapshot(directory: URL = SharedStorage.containerURL) -> WidgetState? {
        guard let (shop, snap) = load(directory) else { return nil }
        let d = Format.delta(today: snap.todayRevenue, yesterday: snap.yesterdayRevenue)
        let target = shop.dailyTarget.flatMap { $0 > 0 ? $0 : nil }
        let targetPct = target.map { min(1, max(0, snap.todayRevenue / $0)) }
        return WidgetState(
            shopName: shop.name,
            revenueText: shop.fmt(snap.todayRevenue),
            deltaLabel: d.label,
            deltaUp: d.up,
            targetPct: targetPct,
            targetText: target.map { shop.fmt($0) },
            lastSyncMs: snap.lastSyncEpochMs,
            tintIndex: shop.tintIndex
        )
    }

    static func readWeeklySnapshot(directory: URL = SharedStorage.containerURL) -> WeeklyWidgetState? {
        guard let (shop, snap) = load(directory) else { return nil }
        let week = snap.weekRevenue
        guard !week.isEmpty else { return nil }
        let total = week.reduce(0, +)
        let maxValue = week.max() ?? 0
        let bars = week.map { maxValue > 0 ? $0 / maxValue : 0 }
        // momentum: 2nd half of the week vs 1st half (same as the in-app Reports delta)
        let half = week.count / 2
        let firstHalf = week.prefix(half).reduce(0, +)
        let secondHalf = week.suffix(half).reduce(0, +)
        let d = Format.delta(today: secondHalf, yesterday: firstHalf)
        return WeeklyWidgetState(
            shopName: shop.name,
            weekTotalText: shop.fmt(total),
            deltaLabel: d.label,
            deltaUp: d.up,
            bars: bars,
            todayIndex: min(max(0, snap.todayIndex), week.count - 1),
            lastSyncMs: snap.lastSyncEpochMs
        )
    }

    /// Loads the selected (or first) shop + its snapshot from the shared cache files.
    private static func load(_ directory: URL) -> (ConnectedShop, ShopSnapshot)? {
        let appDataURL = directory.appendingPathComponent("app-data.json")
        guard let appData = try? Data(contentsOf: appDataURL),
              let data = try? decoder.decode(AppData.self, from: appData) else { return nil }
        guard let shop = data.shops.first(where: { $0.id == data.selectedShopId }) ?? data.shops.first else {
            return nil
        }
        let snapURL = directory.appendingPathComponent("snapshots/\(shop.id).json")
        guard let snapData = try? Data(contentsOf: snapURL),
              let snapshot = try? decoder.decode(ShopSnapshot.self, from: snapData) else { return nil }
        return (shop, snapshot)
    }
}
