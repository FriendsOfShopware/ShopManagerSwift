import Foundation
import ShopwareAdminAPI

/// Joins non-blank parts with a space, falling back to `fallback` when the result is empty.
private func joinedName(_ parts: [String?], fallback: String) -> String {
    let joined = parts.compactMap { $0 }.joined(separator: " ")
    return joined.isEmpty ? fallback : joined
}

/// Shared by the snapshot (ShopwareDataSource) and the live orders listing.
func orderListCriteria() -> Criteria {
    let criteria = Criteria()
        .addSorting("orderDateTime", "DESC")
        .addSorting("id", "DESC")
        .addAssociation("stateMachineState")
        .addAssociation("orderCustomer")
        .addAssociation("currency")
        .addAssociation("salesChannel")
        .addAssociation("transactions.stateMachineState").addAssociation("transactions.paymentMethod")
        .addAssociation("deliveries.stateMachineState").addAssociation("deliveries.shippingMethod")
        .addIncludes("order", ["id", "orderNumber", "amountTotal", "orderDateTime", "stateMachineState", "orderCustomer", "currency", "salesChannel", "transactions", "deliveries", "primaryOrderTransactionId", "primaryOrderDeliveryId"])
        .addIncludes("state_machine_state", ["id", "name", "technicalName", "translated"])
        .addIncludes("order_customer", ["firstName", "lastName", "email", "company"])
        .addIncludes("currency", ["isoCode"])
        .addIncludes("sales_channel", ["name", "translated"])
        .addIncludes("order_transaction", ["id", "createdAt", "stateMachineState", "paymentMethod"])
        .addIncludes("order_delivery", ["id", "createdAt", "stateMachineState", "shippingMethod", "shippingCosts"])
        .addIncludes("payment_method", ["name", "translated"])
        .addIncludes("shipping_method", ["name", "translated"])
    criteria.getAssociation("transactions").addSorting("createdAt", "DESC").addSorting("id")
    criteria.getAssociation("deliveries").addSorting("createdAt").addSorting("id")
    return criteria
}

func parseOrder(_ o: SwEntity, now: Int64) -> RecentOrder {
    let state = o.entity("stateMachineState")
    let cust = o.entity("orderCustomer")
    var result = RecentOrder(
        id: o.id ?? "",
        orderNumber: o.string("orderNumber") ?? "—",
        customer: joinedName([cust?.string("firstName"), cust?.string("lastName")], fallback: String(localized: "Guest")),
        state: state.map { $0.translated("name") ?? "—" } ?? String(localized: "Open"),
        stateTechnical: state?.string("technicalName") ?? "open",
        amount: o.double("amountTotal") ?? 0.0,
        currencyIso: o.entity("currency")?.string("isoCode"),
        placedMs: o.date("orderDateTime")?.epochMs ?? now
    )
    let payment = primaryOrderTransaction(o)
    let delivery = primaryOrderDelivery(o)
    result.customerEmail = cust?.string("email")
    result.company = cust?.string("company")
    result.salesChannel = o.entity("salesChannel")?.translated("name")
    result.paymentState = payment?.entity("stateMachineState")?.translated("name")
    result.paymentStateTechnical = payment?.entity("stateMachineState")?.string("technicalName")
    result.deliveryState = delivery?.entity("stateMachineState")?.translated("name")
    result.deliveryStateTechnical = delivery?.entity("stateMachineState")?.string("technicalName")
    result.paymentMethod = payment?.entity("paymentMethod")?.translated("name")
    result.shippingMethod = delivery?.entity("shippingMethod")?.translated("name")
    return result
}

func customerListCriteria() -> Criteria {
    Criteria()
        .addSorting("orderTotalAmount", "DESC")
        .addIncludes("customer", ["id", "firstName", "lastName", "email", "customerNumber", "active", "guest", "orderCount", "orderTotalAmount"])
}

extension ShopApi {
    /// Full, stable history across the order and every payment/delivery record.
    func fetchOrderTimeline(referencedIds: [String]) async throws -> [OrderTimelineEntry] {
        guard !referencedIds.isEmpty else { return [] }
        let criteria = Criteria().setLimit(100).setTotalCountMode(.exact)
            .addFilter(Criteria.equalsAny("referencedId", referencedIds.map { .string($0) }))
            .addSorting("createdAt", "DESC").addSorting("id", "DESC")
            .addAssociation("toStateMachineState").addAssociation("fromStateMachineState")
            .addAssociation("user").addAssociation("integration")
        var entries: [OrderTimelineEntry] = []
        var page = 1
        var seen = Set<String>()
        while true {
            try Task.checkCancellation()
            let result = try await repository("state-machine-history").search(criteria.setPage(page))
            for row in result.data {
                guard let id = row.id, seen.insert(id).inserted,
                      let state = row.entity("toStateMachineState"), let createdAt = row.date("createdAt") else { continue }
                let user = row.entity("user")
                let name = [user?.string("firstName"), user?.string("lastName")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                let actor = name.isEmpty ? user?.string("username") ?? row.entity("integration")?.string("label") : name
                entries.append(OrderTimelineEntry(id: id, entity: row.string("entityName") ?? "order",
                    toStateName: state.translated("name") ?? state.string("technicalName") ?? "—",
                    toStateTechnical: state.string("technicalName") ?? "", userLabel: actor, createdAtMs: createdAt.epochMs,
                    fromStateName: row.entity("fromStateMachineState")?.translated("name"),
                    fromStateTechnical: row.entity("fromStateMachineState")?.string("technicalName")))
            }
            if result.data.isEmpty || page * 100 >= result.total { break }
            page += 1
        }
        return entries.sorted { $0.createdAtMs == $1.createdAtMs ? $0.id < $1.id : $0.createdAtMs < $1.createdAtMs }
    }
}
