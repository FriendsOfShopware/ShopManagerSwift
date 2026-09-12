import Foundation
import ShopwareAdminAPI

/// Composes the offline-first Home `ShopSnapshot` from many parallel queries, and provides the
/// live order-detail fetch + small order writes. Rule: the snapshot is small overview data for
/// Home only — listings and detail screens query live through repositories, never the snapshot.
struct ShopwareDataSource: Sendable {
    let apiFor: @Sendable (ConnectedShop) -> ShopApi

    func fetchSnapshot(shop: ConnectedShop, lowStockThreshold: Int) async throws -> ShopSnapshot {
        let api = apiFor(shop)
        let zone = TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone

        let today = cal.startOfDay(for: Date())
        // weekDates: 6 days ago … today (oldest first)
        let weekDates: [Date] = (0...6).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let weekStart = weekDates.first!
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!
        let weekStartIso = isoInstant(weekStart)
        let threeDaysAgoIso = isoInstant(threeDaysAgo)
        let sinceDay = isoDateOnly(weekStart)

        let canOrders = shop.canRead("order")
        let empty = SearchResult(total: 0, data: [], aggregations: .object([:]))

        async let dailyTask: [String: (count: Int, revenue: Double)] = {
            guard canOrders else { return [:] }
            return await fetchDailyStats(api, since: sinceDay, zone: zone.identifier, weekStartIso: weekStartIso)
        }()

        async let openOrdersTask: Int = {
            guard canOrders else { return 0 }
            return try await api.repository("order").search(
                Criteria()
                    .setLimit(1)
                    .setTotalCountMode(.exact)
                    .addFilter(Criteria.equals("stateMachineState.technicalName", "open"))
            ).total
        }()

        async let unpaidTask: Int = {
            guard canOrders else { return 0 }
            return try await api.repository("order").search(
                Criteria()
                    .setLimit(1)
                    .setTotalCountMode(.exact)
                    .addFilter(Criteria.equals("transactions.stateMachineState.technicalName", "open"))
                    .addFilter(Criteria.range("orderDateTime", lte: .string(threeDaysAgoIso)))
                    .addFilter(Criteria.not("and", Criteria.equals("stateMachineState.technicalName", "cancelled")))
            ).total
        }()

        async let lowStockTask: SearchResult = {
            guard shop.canRead("product") else { return empty }
            return try await api.repository("product").search(
                Criteria()
                    .setLimit(5)
                    .setTotalCountMode(.exact)
                    .addFilter(Criteria.range("stock", lte: .int(lowStockThreshold)))
                    .addFilter(Criteria.equals("active", true))
                    .addSorting("stock")
                    .addIncludes("product", ["id", "name", "stock", "translated"])
            )
        }()

        async let recentTask: SearchResult = {
            guard canOrders else { return empty }
            return try await api.repository("order").search(orderListCriteria().setLimit(8))
        }()

        async let customersTask: SearchResult = {
            guard shop.canRead("customer") else { return empty }
            return try await api.repository("customer").search(customerListCriteria().setLimit(8))
        }()

        async let promotionsTask: SearchResult = {
            guard shop.canRead("promotion") else { return empty }
            return try await api.repository("promotion").search(promoCriteria().setLimit(20))
        }()

        async let productsTask: SearchResult = {
            guard canOrders else { return empty }
            return try await api.repository("order-line-item").search(
                Criteria()
                    .setLimit(1)
                    .setTotalCountMode(.none)
                    .addFilter(Criteria.equals("type", "product"))
                    .addFilter(Criteria.range("order.orderDateTime", gte: .string(weekStartIso)))
                    .addAggregation(termsAgg("qty", "label", "q", "quantity"))
                    // line-item prices are in the order's currency — nest by factor to normalize
                    .addAggregation(
                        Criteria.terms(
                            "rev", "label",
                            limit: 10,
                            sort: Criteria.sort("_count", "DESC"),
                            aggregation: Criteria.terms(
                                "byFactor", "order.currencyFactor",
                                aggregation: Criteria.sum("r", "totalPrice")
                            )
                        )
                    )
            )
        }()

        // Missing product_review ACL must not fail the whole snapshot.
        async let pendingReviewsTask: Int = {
            guard shop.canRead("product_review") else { return 0 }
            do {
                return try await api.repository("product-review").search(
                    Criteria()
                        .setLimit(1)
                        .setTotalCountMode(.exact)
                        .addFilter(Criteria.equals("status", false))
                ).total
            } catch {
                return 0
            }
        }()

        let statsByDate = await dailyTask
        let weekRevenue = weekDates.map { statsByDate[isoDateOnly($0)]?.revenue ?? 0.0 }
        let ordersToday = statsByDate[isoDateOnly(today)]?.count ?? 0

        let lowStockResult = try await lowStockTask
        let lowStockItems = lowStockResult.data.map {
            LowStockItem(name: $0.translated("name") ?? "—", stock: $0.int("stock") ?? 0, id: $0.id ?? "")
        }

        let now = Date().epochMs
        let recentOrders = try await recentTask.data.map { parseOrder($0, now: now) }

        let topCustomers: [TopCustomer] = try await customersTask.data.compactMap { c in
            let name = [c.string("firstName"), c.string("lastName")].compactMap { $0 }.joined(separator: " ")
            let spend = c.double("orderTotalAmount") ?? 0.0
            guard !name.isEmpty, spend > 0 else { return nil }
            return TopCustomer(name: name, orderCount: c.int("orderCount") ?? 0, totalSpend: spend)
        }

        let nowDate = Date()
        let promos = try await promotionsTask.data.map { parsePromo($0, nowDate, shop) }

        let productsResult = try await productsTask
        let qtyByLabel = Dictionary(
            productsResult.buckets("qty").map { ($0.key, $0.sum("q")) },
            uniquingKeysWith: { a, _ in a }
        )
        let revByLabel = Dictionary(
            productsResult.buckets("rev").map { label -> (String, Double) in
                let rev = label.buckets("byFactor").reduce(0.0) { acc, fb in
                    let factor = Double(fb.key).flatMap { $0 > 0 ? $0 : nil } ?? 1.0
                    return acc + fb.sum("r") / factor
                }
                return (label.key, rev)
            },
            uniquingKeysWith: { a, _ in a }
        )
        let topProducts = qtyByLabel
            .filter { !$0.key.isEmpty }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { TopProduct(name: $0.key, quantity: Int($0.value), revenue: revByLabel[$0.key] ?? 0.0) }

        return ShopSnapshot(
            todayRevenue: weekRevenue.last ?? 0,
            yesterdayRevenue: weekRevenue.count >= 2 ? weekRevenue[weekRevenue.count - 2] : 0,
            ordersToday: ordersToday,
            openOrders: try await openOrdersTask,
            unpaidOrders: try await unpaidTask,
            lowStockCount: lowStockResult.total,
            lowStockItems: lowStockItems,
            weekRevenue: weekRevenue,
            todayIndex: 6,
            recentOrders: recentOrders,
            topCustomers: topCustomers,
            promos: promos,
            topProducts: topProducts,
            pendingReviews: await pendingReviewsTask,
            shopwareVersion: nil,
            lastSyncEpochMs: now
        )
    }

    /// date → (orderCount, revenue). Primary: /_admin/dashboard/order-amount (timezone-aware, same
    /// source as sw-dashboard; includes cancelled, normalizes by currency factor). The fallback
    /// histogram diverges: UTC-day buckets, excludes cancelled, sums raw amountTotal.
    private func fetchDailyStats(
        _ api: ShopApi,
        since: String,
        zone: String,
        weekStartIso: String
    ) async -> [String: (count: Int, revenue: Double)] {
        if let primary = try? await api.dashboard.orderAmount(since: since, timezone: zone, paid: false) {
            return primary
        }
        // amountTotal is in the order's currency — bucket by currencyFactor and divide, so
        // mixed-currency days sum in the shop's default currency (like the dashboard endpoint).
        guard let result = try? await api.repository("order").search(
            Criteria()
                .setLimit(1)
                .setTotalCountMode(.none)
                .addFilter(Criteria.range("orderDateTime", gte: .string(weekStartIso)))
                .addFilter(Criteria.not("and", Criteria.equals("stateMachineState.technicalName", "cancelled")))
                .addAggregation(
                    Criteria.terms(
                        "byFactor", "currencyFactor",
                        aggregation: Criteria.histogram(
                            "daily", "orderDateTime", interval: "day",
                            aggregation: Criteria.sum("revenue", "amountTotal")
                        )
                    )
                )
        ) else { return [:] }

        var merged: [String: (count: Int, revenue: Double)] = [:]
        for factorBucket in result.buckets("byFactor") {
            let factor = Double(factorBucket.key).flatMap { $0 > 0 ? $0 : nil } ?? 1.0
            for day in factorBucket.buckets("daily") {
                let date = String(day.key.prefix(10))
                let prev = merged[date] ?? (0, 0.0)
                merged[date] = (prev.count + day.count, prev.revenue + day.sum("revenue") / factor)
            }
        }
        return merged
    }

    private func termsAgg(_ name: String, _ field: String, _ nestedName: String, _ sumField: String) -> JSONValue {
        Criteria.terms(
            name, field,
            limit: 10,
            sort: Criteria.sort("_count", "DESC"),
            aggregation: Criteria.sum(nestedName, sumField)
        )
    }
}

// MARK: - Date helpers (UTC ISO strings for criteria values)

/// ISO-8601 instant string ("2026-06-11T08:06:24Z") for a Date — matches Instant.toString().
private func isoInstant(_ date: Date) -> String {
    date.ISO8601Format(.iso8601)
}

/// "yyyy-MM-dd" in UTC — for the dashboard `since` param and day-bucket keys.
private func isoDateOnly(_ date: Date) -> String {
    let style = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: TimeZone(identifier: "UTC")!)
        .year().month().day()
    return date.formatted(style)
}

// MARK: - Orders: detail + state transitions + small writes

extension ShopApi {
    func setInternalComment(orderId: String, comment: String?) async throws {
        try await repository("order").patch(orderId, .object(["internalComment": nullableField(comment)]))
    }

    func setTrackingCodes(deliveryId: String, codes: [String]) async throws {
        try await repository("order-delivery").patch(
            deliveryId, .object(["trackingCodes": .array(codes.map { .string($0) })])
        )
    }
}
