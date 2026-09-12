import SwiftUI
import ShopwareAdminAPI

/// Shared options loader for order, payment, and delivery state filters.
private func stateOptions(_ machine: String) -> @Sendable (ShopApi) async throws -> [FilterOption] {
    { api in
        try await api.repository("state-machine-state").search(
            Criteria()
                .setLimit(50)
                .addFilter(Criteria.equals("stateMachine.technicalName", .string(machine)))
                .addSorting("name")
                .addIncludes("state_machine_state", ["id", "name", "translated"])
        ).data.compactMap { s in s.id.map { FilterOption(id: $0, label: s.translated("name") ?? "—") } }
    }
}

@MainActor
@Observable
final class OrdersViewModel: ListingViewModel<RecentOrder> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<RecentOrder> {
        // NOTE: transactions./deliveries. paths are used (not primaryOrderTransaction/Delivery
        // which aren't reliably populated on 6.7).
        let filters: [ListingFilter] = [
            .options(key: "orderStatus", label: "Order status", field: "stateMachineState.id",
                     loadOptions: stateOptions("order.state")),
            .options(key: "paymentStatus", label: "Payment status", field: "transactions.stateMachineState.id",
                     loadOptions: stateOptions("order_transaction.state")),
            .options(key: "deliveryStatus", label: "Delivery status", field: "deliveries.stateMachineState.id",
                     loadOptions: stateOptions("order_delivery.state")),
            .dateRange(key: "orderDate", label: "Order date", field: "orderDateTime"),
            .numberRange(key: "orderValue", label: "Order value", field: "amountTotal"),
            .options(key: "paymentMethod", label: "Payment method", field: "transactions.paymentMethod.id",
                     loadOptions: { api in
                         try await api.repository("payment-method").search(
                             Criteria().setLimit(100).addFilter(Criteria.equals("active", true))
                                 .addSorting("name").addIncludes("payment_method", ["id", "name", "translated"])
                         ).data.compactMap { m in m.id.map { FilterOption(id: $0, label: m.translated("name") ?? "—") } }
                     }),
            salesChannelFilter(label: "Sales channel"),
            .existence(key: "documents", label: "Documents", field: "documents.id",
                       hasLabel: "Has documents", hasNotLabel: "No documents"),
        ]

        return ListingState(
            filters: filters,
            source: { try await api.repository("order").search($0) },
            baseCriteria: { orderListCriteria() },
            mapper: { parseOrder($0, now: Date().epochMs) }
        )
    }
}

struct OrdersView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    @State private var vm: OrdersViewModel?

    var body: some View {
        Group {
            if let vm, let listing = vm.listing, let api = vm.api {
                OrdersWorkspace(shop: shop, api: api, listing: listing)
                    .id("\(shop.id)|\(shop.languageId ?? "")")
            } else { ProgressView("Loading orders…") }
        }
        .navigationTitle("Orders")
        .onAppear {
            if vm == nil { vm = OrdersViewModel(repo: model.repo) }
            vm?.start(shop)
        }
        .onChange(of: shop.id) { vm?.start(shop) }
        .onChange(of: shop.languageId) { vm?.start(shop) }
    }
}
