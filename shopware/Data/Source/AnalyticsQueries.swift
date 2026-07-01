import Foundation
import ShopwareAdminAPI

// Analytics aggregations for the Reports tab — modeled on SwagAnalytics' KPI queries. Kept separate
// from ShopwareDataSource (the Home snapshot), per the "snapshot = Home only" rule. Money KPIs
// normalize multi-currency by nesting sums under terms(currencyFactor) and dividing by the bucket
// key — the same idiom the dashboard uses.

private func msISO(_ epochMs: Int64) -> String {
    Date(timeIntervalSince1970: Double(epochMs) / 1000).ISO8601Format(.iso8601)
}

extension AnalyticsFilters {
    /// The shared order filter list (date range + every active filter) — the single point that lets
    /// the filter bar drive all order-based cards.
    func orderFilters() -> [JSONValue] {
        var f: [JSONValue] = [
            Criteria.range("orderDate", gte: .string(msISO(dateRange.fromMs)), lt: .string(msISO(dateRange.toMs))),
        ]
        if !salesChannelIds.isEmpty { f.append(Criteria.equalsAny("salesChannelId", salesChannelIds.map { .string($0) })) }
        if !orderStateIds.isEmpty { f.append(Criteria.equalsAny("stateMachineState.technicalName", orderStateIds.map { .string($0) })) }
        if !paymentStateIds.isEmpty { f.append(Criteria.equalsAny("transactions.stateMachineState.technicalName", paymentStateIds.map { .string($0) })) }
        if !deliveryStateIds.isEmpty { f.append(Criteria.equalsAny("deliveries.stateMachineState.technicalName", deliveryStateIds.map { .string($0) })) }
        if !customerGroupIds.isEmpty { f.append(Criteria.equalsAny("orderCustomer.customer.groupId", customerGroupIds.map { .string($0) })) }
        if !countryIds.isEmpty { f.append(Criteria.equalsAny("billingAddress.countryId", countryIds.map { .string($0) })) }
        return f
    }

    /// The same window length, shifted back one period — for the delta badge.
    func previous() -> AnalyticsFilters {
        let len = dateRange.toMs - dateRange.fromMs
        var copy = self
        copy.dateRange = DateRange(preset: dateRange.preset, fromMs: dateRange.fromMs - len, toMs: dateRange.fromMs)
        return copy
    }
}

private extension Criteria {
    @discardableResult
    func withOrderFilters(_ f: AnalyticsFilters) -> Criteria {
        for filter in f.orderFilters() { addFilter(filter) }
        return self
    }
}

/// terms(currencyFactor) → <metric>; divide each bucket's value by the factor (its key) and sum.
private func normalizedSum(_ factorBuckets: [Bucket]) -> Double {
    factorBuckets.reduce(0.0) { acc, fb in
        let factor = Double(fb.key).flatMap { $0 != 0 ? $0 : nil } ?? 1.0
        return acc + fb.sum() / factor
    }
}

extension ShopApi {
    // MARK: - Time-series KPIs

    func analyticsTotalSales(_ f: AnalyticsFilters) async throws -> TimeSeriesKpi {
        let points = try await salesPoints(f)
        let prev = try await salesPoints(f.previous()).reduce(0.0) { $0 + $1.value }
        return TimeSeriesKpi(points: points, total: points.reduce(0.0) { $0 + $1.value }, previousTotal: prev, isMoney: true)
    }

    private func salesPoints(_ f: AnalyticsFilters) async throws -> [TimePoint] {
        let res = try await repository("order").search(
            Criteria().withOrderFilters(f).setLimit(1).setTotalCountMode(.none)
                .addAggregation(Criteria.terms(
                    "byFactor", "currencyFactor",
                    aggregation: Criteria.histogram(
                        "daily", "orderDateTime", interval: f.dateRange.interval.apiValue,
                        aggregation: Criteria.sum("rev", "amountTotal")
                    )
                ))
        )
        var byDate: [Int64: Double] = [:]
        for fb in res.buckets("byFactor") {
            let factor = Double(fb.key).flatMap { $0 != 0 ? $0 : nil } ?? 1.0
            for day in fb.buckets("daily") {
                let t = parseBucketDate(day.key)
                byDate[t, default: 0] += day.sum("rev") / factor
            }
        }
        return byDate.sorted { $0.key < $1.key }.map { TimePoint(epochMs: $0.key, value: $0.value) }
    }

    /// Single normalized revenue total for the filtered range — used by the cross-shop comparison
    /// so it tracks the selected period.
    func analyticsRevenueTotal(_ f: AnalyticsFilters) async throws -> Double {
        let res = try await repository("order").search(
            Criteria().withOrderFilters(f).setLimit(1).setTotalCountMode(.none)
                .addAggregation(Criteria.terms("byFactor", "currencyFactor", aggregation: Criteria.sum("rev", "amountTotal")))
        )
        return normalizedSum(res.buckets("byFactor"))
    }

    func analyticsOrderCount(_ f: AnalyticsFilters) async throws -> TimeSeriesKpi {
        let points = try await orderCountPoints(f)
        let prev = try await orderCountPoints(f.previous()).reduce(0.0) { $0 + $1.value }
        return TimeSeriesKpi(points: points, total: points.reduce(0.0) { $0 + $1.value }, previousTotal: prev, isMoney: false)
    }

    private func orderCountPoints(_ f: AnalyticsFilters) async throws -> [TimePoint] {
        let res = try await repository("order").search(
            Criteria().withOrderFilters(f).setLimit(1).setTotalCountMode(.none)
                .addAggregation(Criteria.histogram("daily", "orderDateTime", interval: f.dateRange.interval.apiValue))
        )
        return res.buckets("daily").map { TimePoint(epochMs: parseBucketDate($0.key), value: Double($0.count)) }
    }

    func analyticsAvgOrderValue(_ f: AnalyticsFilters) async throws -> TimeSeriesKpi {
        let points = try await avgPoints(f)
        let prevPts = try await avgPoints(f.previous())
        func avgOf(_ pts: [TimePoint]) -> Double {
            let positive = pts.map(\.value).filter { $0 > 0 }
            return positive.isEmpty ? 0 : positive.reduce(0, +) / Double(positive.count)
        }
        return TimeSeriesKpi(points: points, total: avgOf(points), previousTotal: avgOf(prevPts), isMoney: true)
    }

    /// Per-bucket AOV = revenue / order-count for that bucket.
    private func avgPoints(_ f: AnalyticsFilters) async throws -> [TimePoint] {
        let res = try await repository("order").search(
            Criteria().withOrderFilters(f).setLimit(1).setTotalCountMode(.none)
                .addAggregation(Criteria.terms(
                    "byFactor", "currencyFactor",
                    aggregation: Criteria.histogram(
                        "daily", "orderDateTime", interval: f.dateRange.interval.apiValue,
                        aggregation: Criteria.sum("rev", "amountTotal")
                    )
                ))
                .addAggregation(Criteria.histogram("counts", "orderDateTime", interval: f.dateRange.interval.apiValue))
        )
        var revByDate: [Int64: Double] = [:]
        for fb in res.buckets("byFactor") {
            let factor = Double(fb.key).flatMap { $0 != 0 ? $0 : nil } ?? 1.0
            for d in fb.buckets("daily") { revByDate[parseBucketDate(d.key), default: 0] += d.sum("rev") / factor }
        }
        var countByDate: [Int64: Int] = [:]
        for c in res.buckets("counts") { countByDate[parseBucketDate(c.key)] = c.count }
        return revByDate.sorted { $0.key < $1.key }.map { t, rev in
            let c = countByDate[t] ?? 0
            return TimePoint(epochMs: t, value: c > 0 ? rev / Double(c) : 0)
        }
    }

    func analyticsNewCustomers(_ f: AnalyticsFilters) async throws -> TimeSeriesKpi {
        let points = try await newCustomerPoints(f)
        let prev = try await newCustomerPoints(f.previous()).reduce(0.0) { $0 + $1.value }
        return TimeSeriesKpi(points: points, total: points.reduce(0.0) { $0 + $1.value }, previousTotal: prev, isMoney: false)
    }

    private func newCustomerPoints(_ f: AnalyticsFilters) async throws -> [TimePoint] {
        let criteria = Criteria().setLimit(1).setTotalCountMode(.none)
            .addFilter(Criteria.range("createdAt", gte: .string(msISO(f.dateRange.fromMs)), lt: .string(msISO(f.dateRange.toMs))))
            .addAggregation(Criteria.histogram("daily", "createdAt", interval: f.dateRange.interval.apiValue))
        if !f.salesChannelIds.isEmpty {
            criteria.addFilter(Criteria.equalsAny("salesChannelId", f.salesChannelIds.map { .string($0) }))
        }
        let res = try await repository("customer").search(criteria)
        return res.buckets("daily").map { TimePoint(epochMs: parseBucketDate($0.key), value: Double($0.count)) }
    }

    // MARK: - Breakdown KPIs

    func analyticsSalesChannel(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        let res = try await repository("order").search(
            Criteria().withOrderFilters(f).setLimit(1).setTotalCountMode(.none)
                .addAggregation(Criteria.terms(
                    "sc", "salesChannelId", limit: 20,
                    aggregation: Criteria.terms("byFactor", "currencyFactor", aggregation: Criteria.sum("rev", "amountTotal"))
                ))
        )
        let names = await resolveNames("sales-channel", res.buckets("sc").map(\.key))
        let rows = res.buckets("sc").map { b in
            BreakdownRow(id: b.key, label: names[b.key] ?? "—", value: normalizedSum(b.buckets("byFactor")))
        }.sorted { $0.value > $1.value }
        return BreakdownKpi(rows: rows, valueIsMoney: true)
    }

    func analyticsPaymentMethod(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        try await orderTermsBreakdown(f, field: "transactions.paymentMethodId", entity: "payment-method")
    }

    func analyticsShippingMethod(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        try await orderTermsBreakdown(f, field: "deliveries.shippingMethodId", entity: "shipping-method")
    }

    func analyticsCountry(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        try await orderTermsBreakdown(f, field: "billingAddress.countryId", entity: "country")
    }

    private func orderTermsBreakdown(_ f: AnalyticsFilters, field: String, entity: String) async throws -> BreakdownKpi {
        let res = try await repository("order").search(
            Criteria().withOrderFilters(f).setLimit(1).setTotalCountMode(.none)
                .addAggregation(Criteria.terms("t", field, limit: 20))
        )
        let names = await resolveNames(entity, res.buckets("t").map(\.key))
        let rows = res.buckets("t").map { BreakdownRow(id: $0.key, label: names[$0.key] ?? "—", value: Double($0.count)) }
            .sorted { $0.value > $1.value }
        return BreakdownKpi(rows: rows, valueIsMoney: false)
    }

    func analyticsBestSelling(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        try await lineItemQuantityBreakdown(f, field: "productId", entity: "product")
    }

    func analyticsManufacturer(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        try await lineItemQuantityBreakdown(f, field: "product.manufacturerId", entity: "product-manufacturer")
    }

    private func lineItemQuantityBreakdown(_ f: AnalyticsFilters, field: String, entity: String) async throws -> BreakdownKpi {
        let criteria = Criteria().setLimit(1).setTotalCountMode(.none)
            .addFilter(Criteria.equals("type", "product"))
            .addAggregation(Criteria.terms("t", field, limit: 10, aggregation: Criteria.sum("qty", "quantity")))
        for filter in f.orderFilters() { criteria.addFilter(prefixOrder(filter)) }
        let res = try await repository("order-line-item").search(criteria)
        let names = await resolveNames(entity, res.buckets("t").map(\.key))
        let rows = res.buckets("t").map { BreakdownRow(id: $0.key, label: names[$0.key] ?? "—", value: $0.sum("qty")) }
            .sorted { $0.value > $1.value }
        return BreakdownKpi(rows: rows, valueIsMoney: false)
    }

    func analyticsPromotionCode(_ f: AnalyticsFilters) async throws -> BreakdownKpi {
        let criteria = Criteria().setLimit(1).setTotalCountMode(.none)
            .addFilter(Criteria.equals("type", "promotion"))
            .addAggregation(Criteria.terms("t", "label", limit: 15))
        for filter in f.orderFilters() { criteria.addFilter(prefixOrder(filter)) }
        let res = try await repository("order-line-item").search(criteria)
        let rows = res.buckets("t").map { BreakdownRow(id: $0.key, label: $0.key.isEmpty ? "—" : $0.key, value: Double($0.count)) }
            .sorted { $0.value > $1.value }
        return BreakdownKpi(rows: rows, valueIsMoney: false)
    }

    // MARK: - Single-number KPI

    func analyticsCustomerCount(_ f: AnalyticsFilters) async throws -> SingleKpi {
        func crit(_ range: AnalyticsFilters) -> Criteria {
            let c = Criteria().setLimit(1).setTotalCountMode(.exact)
                .addFilter(Criteria.range("createdAt", lt: .string(msISO(range.dateRange.toMs))))
            if !range.salesChannelIds.isEmpty {
                c.addFilter(Criteria.equalsAny("salesChannelId", range.salesChannelIds.map { .string($0) }))
            }
            return c
        }
        let now = Double(try await repository("customer").search(crit(f)).total)
        let before = Double(try await repository("customer").search(crit(f.previous())).total)
        return SingleKpi(value: now, previousValue: before, isMoney: false)
    }

    // MARK: - Helpers

    /// Re-target an order filter onto the order_line_item entity by prefixing field paths with
    /// "order.". salesChannelId/orderDate/etc. live on the parent order from the line-item view.
    private func prefixOrder(_ filter: JSONValue) -> JSONValue {
        guard case var .object(o) = filter, let field = o["field"]?.stringValue else { return filter }
        o["field"] = .string("order.\(field)")
        return .object(o)
    }

    /// id → translated("name") for a set of ids. One follow-up fetch per breakdown. Degrades to nil.
    private func resolveNames(_ entity: String, _ ids: [String]) async -> [String: String] {
        let real = ids.filter { !$0.isEmpty }
        guard !real.isEmpty else { return [:] }
        let alias = entity.replacingOccurrences(of: "-", with: "_")
        guard let data = try? await repository(entity).search(
            Criteria().setIds(real).setLimit(real.count).addIncludes(alias, ["id", "name", "translated"])
        ).data else { return [:] }
        var map: [String: String] = [:]
        for e in data { if let id = e.id { map[id] = e.translated("name") ?? "—" } }
        return map
    }

    // MARK: - Filter-bar options

    func fetchAnalyticsFilterOptions() async -> AnalyticsFilterOptions {
        func simple(_ entity: String, _ sortField: String) async -> [FilterOptionItem] {
            let alias = entity.replacingOccurrences(of: "-", with: "_")
            guard let data = try? await repository(entity).search(
                Criteria().setLimit(100).addSorting(sortField).addIncludes(alias, ["id", "name", "translated"])
            ).data else { return [] }
            return data.compactMap { e in e.id.map { FilterOptionItem(id: $0, label: e.translated("name") ?? "—") } }
        }

        func states(_ machine: String) async -> [FilterOptionItem] {
            guard let data = try? await repository("state-machine-state").search(
                Criteria().setLimit(50)
                    .addFilter(Criteria.equals("stateMachine.technicalName", .string(machine)))
                    .addIncludes("state_machine_state", ["technicalName", "name", "translated"])
            ).data else { return [] }
            return data.compactMap { s in
                s.string("technicalName").map { FilterOptionItem(id: $0, label: s.translated("name") ?? $0) }
            }
        }

        async let sc = simple("sales-channel", "name")
        async let cg = simple("customer-group", "name")
        async let co = simple("country", "name")
        async let os = states("order.state")
        async let ps = states("order_transaction.state")
        async let ds = states("order_delivery.state")
        return await AnalyticsFilterOptions(
            salesChannels: sc, customerGroups: cg, countries: co,
            orderStates: os, paymentStates: ps, deliveryStates: ds
        )
    }
}

/// histogram bucket keys come as "2026-06-12 00:00:00" (space-separated UTC) or ISO; parse
/// leniently → epoch millis.
private func parseBucketDate(_ key: String) -> Int64 {
    let iso = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!)
    let isoFrac = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(identifier: "UTC")!)
    // Space form → append T and Z; offset/ISO forms parse directly.
    let candidates: [String] = {
        if key.contains(" ") { return [key.replacingOccurrences(of: " ", with: "T") + "Z"] }
        if key.hasSuffix("Z") || key.contains("+") { return [key] }
        return [key + "Z", key]
    }()
    for c in candidates {
        if let d = try? isoFrac.parse(c) { return Int64(d.timeIntervalSince1970 * 1000) }
        if let d = try? iso.parse(c) { return Int64(d.timeIntervalSince1970 * 1000) }
    }
    return 0
}
