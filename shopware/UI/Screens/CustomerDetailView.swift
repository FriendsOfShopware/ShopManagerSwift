import SwiftUI
import ShopwareAdminAPI

@MainActor
@Observable
final class CustomerDetailViewModel {
    private let repo: AppRepository
    let shop: ConnectedShop
    let customerId: String

    private(set) var detail: CustomerDetail?
    private(set) var loading = false
    private(set) var error: String?
    /// Paginated order history (total + load-more), mirroring the Android ListingState usage.
    private(set) var orders: ListingState<RecentOrder>?

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
            if orders == nil { orders = makeOrdersListing() }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func makeOrdersListing() -> ListingState<RecentOrder> {
        let api = repo.apiFor(shop)
        let customerId = self.customerId
        let state = ListingState<RecentOrder>(
            pageSize: 10,
            source: { try await api.repository("order").search($0) },
            baseCriteria: {
                orderListCriteria().addFilter(Criteria.equals("orderCustomer.customerId", .string(customerId)))
            },
            mapper: { parseOrder($0, now: Date().epochMs) }
        )
        state.reload()
        return state
    }
}

struct CustomerDetailView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openURL) private var openURL
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
                    if let since = detail.customerSince {
                        Text("Customer since \(since)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                if let url = URL(string: "mailto:\(detail.email)"), !detail.email.isEmpty {
                    Button { openURL(url) } label: { Label(detail.email, systemImage: "envelope") }
                }
                if let phone = detail.phone, let url = phoneURL(phone) {
                    Button { openURL(url) } label: { Label(phone, systemImage: "phone") }
                }

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
                if let lastMs = detail.lastOrderMs {
                    MetricRow(symbol: "clock", label: "Last order", value: relativeAgoText(lastMs))
                }
            }

            if let billing = detail.billingAddress {
                Section("Billing address") { Text(billing) }
            }
            if let shipping = detail.shippingAddress, shipping != detail.billingAddress {
                Section("Shipping address") { Text(shipping) }
            }

            orderHistorySection(vm)
        }
        .groupedListStyle()
    }

    @ViewBuilder
    private func orderHistorySection(_ vm: CustomerDetailViewModel) -> some View {
        if let orders = vm.orders {
            Section {
                if let error = orders.error, orders.items.isEmpty {
                    HStack {
                        Text(error).foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { orders.reload() }
                    }
                } else if orders.items.isEmpty, !orders.loading {
                    Text("No orders").foregroundStyle(.secondary)
                }
                ForEach(orders.items) { order in
                    NavigationLink(value: order.id) {
                        OrderRow(shop: shop, order: order)
                    }
                }
                if orders.items.count < orders.total {
                    Button {
                        orders.loadMore()
                    } label: {
                        if orders.loading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("Load more")
                        }
                    }
                    .disabled(orders.loading)
                }
            } header: {
                Text(orders.total > 0 ? "^[\(orders.total) order](inflect: true)" : "Order history")
            }
        }
    }

    private func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}
