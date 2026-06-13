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
    func fetchOrderDetail(_ orderId: String) async throws -> OrderDetail {
        guard let o = try await repository("order").search(
            Criteria()
                .setLimit(1)
                .addFilter(Criteria.equals("id", .string(orderId)))
                .addAssociation("lineItems")
                .addAssociation("stateMachineState")
                .addAssociation("orderCustomer")
                .addAssociation("deliveries.stateMachineState")
                .addAssociation("deliveries.shippingMethod")
                .addAssociation("deliveries.shippingOrderAddress.country")
                .addAssociation("transactions.stateMachineState")
                .addAssociation("transactions.paymentMethod")
                .addAssociation("documents.documentType")
                .addAssociation("billingAddress.country")
                .addAssociation("currency")
        ).data.first else {
            throw ApiError.notFound(message: "Order not found")
        }

        let delivery = o.entities("deliveries").first
        let transaction = o.entities("transactions").last
        let cust = o.entity("orderCustomer")
        let billing = o.entity("billingAddress")
        let shippingAddr = delivery?.entity("shippingOrderAddress")

        // (entity, entityId, state) sources, skipping any with an empty id.
        var stateSources: [(entity: String, entityId: String, state: SwEntity?)] = [
            ("order", orderId, o.entity("stateMachineState")),
        ]
        if let transaction { stateSources.append(("order_transaction", transaction.id ?? "", transaction.entity("stateMachineState"))) }
        if let delivery { stateSources.append(("order_delivery", delivery.id ?? "", delivery.entity("stateMachineState"))) }
        stateSources = stateSources.filter { !$0.entityId.isEmpty }

        var states: [OrderStateInfo] = []
        for src in stateSources {
            let transitions = (try? await stateMachine.transitions(entity: src.entity, id: src.entityId)) ?? []
            states.append(OrderStateInfo(
                entity: src.entity,
                entityId: src.entityId,
                label: src.entity == "order_transaction" ? "Payment"
                    : src.entity == "order_delivery" ? "Delivery" : "Order",
                stateName: src.state?.translated("name") ?? "—",
                stateTechnical: src.state?.string("technicalName") ?? "open",
                transitions: transitions
            ))
        }

        let priceEntity = o.entity("price")
        let taxes: [TaxLine] = priceEntity?.entities("calculatedTaxes").compactMap { t in
            guard let rate = t.double("taxRate"), let amount = t.double("tax"), amount > 0 else { return nil }
            return TaxLine(rate: rate, amount: amount)
        } ?? []

        let trackingCodes: [String] = {
            guard case let .array(codes)? = delivery?.json["trackingCodes"] else { return [] }
            return codes.compactMap { $0.isNull ? nil : $0.stringValue }
        }()

        let customerName = [cust?.string("firstName"), cust?.string("lastName")]
            .compactMap { $0 }.joined(separator: " ")

        let lineItems = o.entities("lineItems")
            .sorted { ($0.int("position") ?? 0) < ($1.int("position") ?? 0) }
            .map {
                OrderLineItem(
                    label: $0.string("label") ?? "—",
                    quantity: $0.int("quantity") ?? 1,
                    totalPrice: $0.double("totalPrice") ?? 0.0,
                    unitPrice: $0.double("unitPrice") ?? 0.0,
                    productNumber: $0.entity("payload")?.string("productNumber")
                )
            }

        let documents: [OrderDocument] = o.entities("documents").compactMap { d in
            guard let id = d.id, let deepLink = d.string("deepLinkCode") else { return nil }
            let type = d.entity("documentType")
            return OrderDocument(
                id: id,
                deepLinkCode: deepLink,
                typeName: type.flatMap { $0.translated("name") ?? $0.string("name") } ?? "Document",
                typeTechnical: type?.string("technicalName") ?? "",
                number: d.string("documentNumber") ?? ""
            )
        }

        return OrderDetail(
            id: orderId,
            orderNumber: o.string("orderNumber") ?? "—",
            orderDateTime: o.string("orderDateTime").map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") } ?? "",
            customerName: customerName.isEmpty ? "Guest" : customerName,
            customerEmail: cust?.string("email") ?? "",
            currencyIso: o.entity("currency")?.string("isoCode"),
            amountTotal: o.double("amountTotal") ?? 0.0,
            shippingTotal: o.double("shippingTotal") ?? 0.0,
            netTotal: priceEntity?.double("netPrice") ?? 0.0,
            taxes: taxes,
            paymentMethod: transaction?.entity("paymentMethod").map { $0.translated("name") ?? "—" },
            shippingMethod: delivery?.entity("shippingMethod").map { $0.translated("name") ?? "—" },
            deliveryId: delivery?.id,
            trackingCodes: trackingCodes,
            billingAddress: billing.flatMap(formatAddress),
            shippingAddress: shippingAddr.flatMap(formatAddress),
            phone: shippingAddr?.string("phoneNumber") ?? billing?.string("phoneNumber"),
            customerComment: o.string("customerComment").flatMap { $0.isEmpty ? nil : $0 },
            internalComment: o.string("internalComment").flatMap { $0.isEmpty ? nil : $0 },
            lineItems: lineItems,
            states: states,
            documents: documents
        )
    }

    func setInternalComment(orderId: String, comment: String?) async throws {
        try await repository("order").patch(orderId, .object(["internalComment": nullableField(comment)]))
    }

    func setTrackingCodes(deliveryId: String, codes: [String]) async throws {
        try await repository("order-delivery").patch(
            deliveryId, .object(["trackingCodes": .array(codes.map { .string($0) })])
        )
    }
}
