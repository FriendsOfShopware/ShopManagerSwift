import SwiftUI
import ShopwareAdminAPI

private struct OrderStateRow { let id: String; let name: String; let technical: String }

/// Loads the order-state options once; feeds both the quick chips and the filter sheet.
private func loadOrderStates(_ api: ShopApi) async throws -> [OrderStateRow] {
    try await api.repository("state-machine-state").search(
        Criteria()
            .setLimit(50)
            .addFilter(Criteria.equals("stateMachine.technicalName", "order.state"))
            .addSorting("name")
            .addIncludes("state_machine_state", ["id", "name", "technicalName", "translated"])
    ).data.compactMap { s in
        guard let id = s.id else { return nil }
        return OrderStateRow(id: id, name: s.translated("name") ?? "—", technical: s.string("technicalName") ?? "")
    }
}

/// Options loader for a given state machine (payment/delivery state).
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
    private(set) var quickFilters: [QuickFilter] = []

    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<RecentOrder> {
        quickFilters = []
        // One order-state fetch feeds both the quick chips and the filter sheet.
        let statesTask = Task { try? await loadOrderStates(api) }

        Task {
            guard let states = await statesTask.value else { return }
            let quick: [(String, String)] = [
                ("Open", "open"), ("In progress", "in_progress"),
                ("Done", "completed"), ("Cancelled", "cancelled"),
            ]
            quickFilters = quick.compactMap { label, technical in
                guard let state = states.first(where: { $0.technical == technical }) else { return nil }
                return QuickFilter(key: "orderStatus", label: LocalizedStringKey(label), value: .options([state.id]))
            }
        }

        // NOTE: transactions./deliveries. paths are used (not primaryOrderTransaction/Delivery
        // which aren't reliably populated on 6.7).
        let filters: [ListingFilter] = [
            .options(key: "orderStatus", label: "Order status", field: "stateMachineState.id",
                     loadOptions: { api in
                         (try? await loadOrderStates(api))?.map { FilterOption(id: $0.id, label: $0.name) } ?? []
                     }),
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

/// Orders listing. On expanded width (iPad/Mac) the NavigationStack-based detail becomes a
/// split view automatically via the surrounding navigation; rows push the order detail.
struct OrdersView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    @State private var vm: OrdersViewModel?
    #if os(macOS)
    @State private var navOrderId: String?
    #endif

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                listingContent(listing)
                    .navigationDestination(for: String.self) { orderId in
                        OrderDetailView(shop: shop, orderId: orderId)
                    }
            } else {
                ProgressView()
            }
        }
        #if os(macOS)
        .navigationDestination(item: $navOrderId) { orderId in
            OrderDetailView(shop: shop, orderId: orderId)
        }
        #endif
        .navigationTitle("Orders")
        .onAppear {
            if vm == nil { vm = OrdersViewModel(repo: model.repo) }
            vm?.start(shop)
        }
        .onChange(of: shop.id) { vm?.start(shop) }
    }

    @ViewBuilder
    private func listingContent(_ listing: ListingState<RecentOrder>) -> some View {
        #if os(macOS)
        MacListingTable(
            state: listing,
            api: vm?.api,
            searchPrompt: "Search orders",
            onActivate: { navOrderId = $0.id },
            columns: {
                TableColumn("Order") { Text("#\($0.orderNumber)").font(.body.monospacedDigit()) }
                    .width(min: 80, ideal: 100)
                TableColumn("Customer") { Text($0.customer) }
                TableColumn("Status") { StatusBadge(label: $0.state, tone: stateTone($0.stateTechnical)) }
                    .width(min: 90, ideal: 120)
                TableColumn("Total") { order in
                    Text(shop.fmt(order.amount, iso: order.currencyIso))
                        .font(.body.weight(.semibold)).monospacedDigit()
                }
                .width(min: 80, ideal: 110)
            },
            rowMenu: { order in
                Button("Open") { navOrderId = order.id }
            }
        )
        #else
        ListingScaffold(
            state: listing,
            api: vm?.api,
            searchPrompt: "Search orders",
            quickChips: chips(for: listing)
        ) { order in
            NavigationLink(value: order.id) {
                OrderRow(shop: shop, order: order)
            }
        }
        #endif
    }

    private func chips(for listing: ListingState<RecentOrder>) -> [QuickChip] {
        (vm?.quickFilters ?? []).map { qf in
            let isOn = listing.activeValues[qf.key] == qf.value
            return QuickChip(label: qf.label, isOn: isOn) {
                listing.setFilterValue(qf.key, isOn ? nil : qf.value)
            }
        }
    }
}
