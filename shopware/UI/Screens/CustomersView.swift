import SwiftUI
import ShopwareAdminAPI

private func mapCustomer(_ c: SwEntity) -> CustomerRow {
    let name = [c.string("firstName"), c.string("lastName")].compactMap { $0 }.joined(separator: " ")
    return CustomerRow(
        id: c.id ?? "",
        name: name.isEmpty ? "—" : name,
        orderCount: c.int("orderCount") ?? 0,
        totalSpend: c.double("orderTotalAmount") ?? 0.0
    )
}

@MainActor
@Observable
final class CustomersViewModel: ListingViewModel<CustomerRow> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<CustomerRow> {
        let filters: [ListingFilter] = [
            .options(key: "group", label: "Group", field: "group.id", loadOptions: { api in
                try await api.repository("customer-group").search(
                    Criteria().setLimit(100).addSorting("name")
                        .addIncludes("customer_group", ["id", "name", "translated"])
                ).data.compactMap { g in g.id.map { FilterOption(id: $0, label: g.translated("name") ?? "—") } }
            }),
            .bool(key: "accountStatus", label: "Account status", field: "active",
                  trueLabel: "Active", falseLabel: "Disabled"),
            .numberRange(key: "orderCount", label: "Order count", field: "orderCount"),
            salesChannelFilter(label: "Sales channel"),
        ]
        return ListingState(
            filters: filters,
            source: { try await api.repository("customer").search($0) },
            baseCriteria: { customerListCriteria() },
            mapper: mapCustomer
        )
    }
}

struct CustomersView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    @State private var vm: CustomersViewModel?

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                ListingScaffold(state: listing, api: vm.api, searchPrompt: "Search customers") { customer in
                    NavigationLink(value: CustomerRoute(id: customer.id)) {
                        CustomerRowView(shop: shop, customer: customer)
                    }
                }
                .navigationDestination(for: CustomerRoute.self) { route in
                    CustomerDetailView(shop: shop, customerId: route.id)
                }
                .navigationDestination(for: String.self) { orderId in
                    OrderDetailView(shop: shop, orderId: orderId)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Customers")
        .onAppear {
            if vm == nil { vm = CustomersViewModel(repo: model.repo) }
            vm?.start(shop)
        }
    }
}

/// Distinguishes a customer route from a bare order-id route in the same stack.
struct CustomerRoute: Hashable { let id: String }

struct CustomerRowView: View {
    let shop: ConnectedShop
    let customer: CustomerRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).lineLimit(1)
                Text("^[\(customer.orderCount) order](inflect: true)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if customer.totalSpend > 0 {
                Text(shop.fmt(customer.totalSpend))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
