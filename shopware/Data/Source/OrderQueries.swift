import Foundation
import ShopwareAdminAPI

/// Joins non-blank parts with a space, falling back to `fallback` when the result is empty.
private func joinedName(_ parts: [String?], fallback: String) -> String {
    let joined = parts.compactMap { $0 }.joined(separator: " ")
    return joined.isEmpty ? fallback : joined
}

/// Shared by the snapshot (ShopwareDataSource) and the live orders listing.
func orderListCriteria() -> Criteria {
    Criteria()
        .addSorting("orderDateTime", "DESC")
        .addAssociation("stateMachineState")
        .addAssociation("orderCustomer")
        .addAssociation("currency")
        .addIncludes("order", ["id", "orderNumber", "amountTotal", "orderDateTime", "stateMachineState", "orderCustomer", "currency"])
        .addIncludes("state_machine_state", ["name", "technicalName"])
        .addIncludes("order_customer", ["firstName", "lastName"])
        .addIncludes("currency", ["isoCode"])
}

func parseOrder(_ o: SwEntity, now: Int64) -> RecentOrder {
    let state = o.entity("stateMachineState")
    let cust = o.entity("orderCustomer")
    return RecentOrder(
        id: o.id ?? "",
        orderNumber: o.string("orderNumber") ?? "—",
        customer: joinedName([cust?.string("firstName"), cust?.string("lastName")], fallback: "Guest"),
        state: state.map { $0.translated("name") ?? "—" } ?? "Open",
        stateTechnical: state?.string("technicalName") ?? "open",
        amount: o.double("amountTotal") ?? 0.0,
        currencyIso: o.entity("currency")?.string("isoCode"),
        placedMs: o.date("orderDateTime")?.epochMs ?? now
    )
}

func customerListCriteria() -> Criteria {
    Criteria()
        .addSorting("orderTotalAmount", "DESC")
        .addIncludes("customer", ["id", "firstName", "lastName", "email", "customerNumber", "active", "guest", "orderCount", "orderTotalAmount"])
}

extension ShopApi {
    /// Chronological state history across an order and its payment/delivery records.
    /// `referencedIds` are the order id + transaction id + delivery id (from OrderDetail.states).
    func fetchOrderTimeline(referencedIds: [String]) async throws -> [OrderTimelineEntry] {
        if referencedIds.isEmpty { return [] }
        let rows = try await repository("state-machine-history").search(
            Criteria()
                .setLimit(100)
                .addFilter(Criteria.equalsAny("referencedId", referencedIds.map { JSONValue.string($0) }))
                .addSorting("createdAt", "ASC")
                .addAssociation("toStateMachineState")
                .addAssociation("user")
                .addIncludes("state_machine_history", ["entityName", "createdAt", "toStateMachineState", "user"])
                .addIncludes("state_machine_state", ["name", "translated", "technicalName"])
                .addIncludes("user", ["firstName", "lastName", "username"])
        ).data

        return rows.compactMap { h -> OrderTimelineEntry? in
            guard let to = h.entity("toStateMachineState") else { return nil }
            guard let created = h.date("createdAt")?.epochMs else { return nil }
            // Mirrors Kotlin's `user?.let { name.ifBlank { username } }`: when the user is present
            // but the joined name is blank, fall back to username — which may itself be nil, so
            // userLabel can stay nil (the UI renders that as "automatic").
            var userLabel: String?
            if let u = h.entity("user") {
                let name = [u.string("firstName"), u.string("lastName")].compactMap { $0 }.joined(separator: " ")
                userLabel = name.isEmpty ? u.string("username") : name
            }
            return OrderTimelineEntry(
                entity: h.string("entityName") ?? "order",
                toStateName: to.translated("name") ?? to.string("technicalName") ?? "—",
                toStateTechnical: to.string("technicalName") ?? "",
                userLabel: userLabel,
                createdAtMs: created
            )
        }
    }
}
