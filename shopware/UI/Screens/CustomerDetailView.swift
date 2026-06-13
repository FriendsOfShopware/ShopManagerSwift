import SwiftUI
import ShopwareAdminAPI

@MainActor
@Observable
final class CustomerDetailViewModel {
    private let repo: AppRepository
    let shop: ConnectedShop
    let customerId: String

    private(set) var detail: CustomerDetail?
    private(set) var orders: [RecentOrder] = []
    private(set) var loading = false
    private(set) var error: String?

    init(repo: AppRepository, shop: ConnectedShop, customerId: String) {
        self.repo = repo
        self.shop = shop
        self.customerId = customerId
    }

    func load() async {
        loading = true
        error = nil
        do {
            detail = try await repo.customerDetail(shop, customerId: customerId)
            await loadOrders()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func loadOrders() async {
        let api = repo.apiFor(shop)
        let criteria = orderListCriteria()
            .setLimit(20)
            .addFilter(Criteria.equals("orderCustomer.customerId", .string(customerId)))
        if let result = try? await api.repository("order").search(criteria) {
            orders = result.data.map { parseOrder($0, now: Date().epochMs) }
        }
    }
}

struct CustomerDetailView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let customerId: String

    @State private var vm: CustomerDetailViewModel?
    @State private var showingEdit = false

    var body: some View {
        Group {
            if let vm, let detail = vm.detail {
                content(detail, vm: vm)
            } else if let vm, let error = vm.error {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Customer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if vm?.detail != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEdit = true } label: { Image(systemName: "pencil") }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let detail = vm?.detail {
                CustomerEditSheet(shop: shop, detail: detail) {
                    Task { await vm?.load() }
                }
            }
        }
        .task {
            if vm == nil { vm = CustomerDetailViewModel(repo: model.repo, shop: shop, customerId: customerId) }
            await vm?.load()
        }
    }

    private func content(_ detail: CustomerDetail, vm: CustomerDetailViewModel) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.name).font(.title2.weight(.semibold))
                    Text(detail.email).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                if let group = detail.group {
                    LabeledContent("Group", value: group)
                }
                LabeledContent("Status") {
                    StatusBadge(label: detail.active ? "Active" : "Disabled",
                                tone: detail.active ? .done : .error)
                }
                if detail.guest {
                    LabeledContent("Account", value: String(localized: "Guest"))
                }
                if !detail.customerNumber.isEmpty {
                    LabeledContent("Customer no.", value: detail.customerNumber)
                }
            }

            Section {
                MetricRow(symbol: "doc.text", label: "Orders", value: "\(detail.orderCount)")
                MetricRow(symbol: "creditcard", label: "Spent", value: shop.fmt(detail.totalSpend))
            }

            if let billing = detail.billingAddress {
                Section("Billing address") { Text(billing) }
            }
            if let shipping = detail.shippingAddress, shipping != detail.billingAddress {
                Section("Shipping address") { Text(shipping) }
            }

            Section("Order history") {
                if vm.orders.isEmpty {
                    Text("No orders").foregroundStyle(.secondary)
                }
                ForEach(vm.orders) { order in
                    NavigationLink(value: order.id) {
                        OrderRow(shop: shop, order: order)
                    }
                }
            }
        }
        .groupedListStyle()
    }
}
