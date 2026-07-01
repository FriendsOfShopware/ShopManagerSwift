import Foundation
import Observation
import ShopwareAdminAPI

/// Drives the Reports/Analytics tab: loads all 12 KPIs independently (each card can load/fail on its
/// own), a debounced filter apply, and per-shop revenue for the cross-shop comparison. Re-inits on
/// shop/language change. The Apple analogue of the Android `ReportsViewModel`.
@MainActor
@Observable
final class ReportsViewModel {
    let repo: AppRepository
    private(set) var shop: ConnectedShop?
    private(set) var filters: AnalyticsFilters
    private(set) var kpiStates: [KpiType: KpiState] = [:]
    private(set) var options: AnalyticsFilterOptions?
    /// Per-shop revenue for the selected range (nil entry = loading / failed).
    private(set) var shopRevenues: [String: Double?] = [:]

    @ObservationIgnored private var key: String?
    @ObservationIgnored private var comparableShops: [ConnectedShop] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init(repo: AppRepository) {
        self.repo = repo
        self.filters = AnalyticsFilters(dateRange: ReportsViewModel.range(for: .last7))
    }

    func start(_ shop: ConnectedShop, allShops: [ConnectedShop]) {
        comparableShops = allShops
        let newKey = "\(shop.id)|\(shop.languageId ?? "")"
        if key == newKey { return }
        key = newKey
        self.shop = shop
        filters = AnalyticsFilters(dateRange: ReportsViewModel.range(for: .last7))
        Task { options = await repo.analyticsFilterOptions(shop) }
        reload()
    }

    func applyFilters(_ new: AnalyticsFilters) {
        filters = new
        // debounce so toggling several filters doesn't fire 12×N requests
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            reload()
        }
    }

    func setPreset(_ preset: DateRange.Preset) {
        var new = filters
        new.dateRange = Self.range(for: preset)
        filters = new
        reload()
    }

    func reload() {
        guard let shop else { return }
        generation += 1
        let gen = generation
        let f = filters

        for type in KpiType.allCases {
            kpiStates[type] = .loading
            Task {
                let result: KpiState
                do {
                    result = try await repo.loadKpi(shop, type: type, filters: f)
                } catch {
                    result = .error((error as? ApiError)?.message ?? error.localizedDescription)
                }
                if gen == generation { kpiStates[type] = result }
            }
        }

        if comparableShops.count > 1 {
            for cs in comparableShops {
                shopRevenues[cs.id] = Double?.none
                Task {
                    let rev = try? await repo.loadShopRevenue(cs, filters: f)
                    if gen == generation { shopRevenues[cs.id] = rev }
                }
            }
        }
    }

    func retry(_ type: KpiType) {
        guard let shop else { return }
        let gen = generation
        let f = filters
        kpiStates[type] = .loading
        Task {
            let result: KpiState
            do {
                result = try await repo.loadKpi(shop, type: type, filters: f)
            } catch {
                result = .error((error as? ApiError)?.message ?? error.localizedDescription)
            }
            if gen == generation { kpiStates[type] = result }
        }
    }

    /// Resolve a preset to a [fromMs, toMs) window at local midnight boundaries.
    static func range(for preset: DateRange.Preset) -> DateRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let toMs = Int64(startOfTomorrow.timeIntervalSince1970 * 1000) // exclusive = end of today
        let days: Int = switch preset {
        case .today: 1
        case .last7: 7
        case .last30: 30
        case .last90: 90
        case .custom: 7
        }
        let from = cal.date(byAdding: .day, value: -days, to: startOfTomorrow)!
        let fromMs = Int64(from.timeIntervalSince1970 * 1000)
        if preset == .custom {
            return DateRange(preset: preset, fromMs: fromMs, toMs: Int64(Date().timeIntervalSince1970 * 1000))
        }
        return DateRange(preset: preset, fromMs: fromMs, toMs: toMs)
    }
}
