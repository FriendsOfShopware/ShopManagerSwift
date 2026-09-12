import SwiftUI
import ShopwareAdminAPI

struct OrdersWorkspace: View {
    let shop: ConnectedShop
    let api: ShopApi
    @Bindable var listing: ListingState<RecentOrder>
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var permissions = AdminPermissions()
    @State private var permissionError: String?
    @State private var search = ""
    @State private var filters = false
    @State private var selection = Set<String>()
    @State private var selecting = false
    @State private var orderID: String?
    @State private var creating = false
    @State private var bulk: OrderBulkAction?
    @State private var width: CGFloat = 0
    @State private var sorting = [KeyPathComparator(\RecentOrder.placedMs, order: .reverse)]

    private var useTable: Bool {
        #if os(macOS)
        !typeSize.isAccessibilitySize
        #else
        width >= 900 && !typeSize.isAccessibilitySize
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = permissionError { OrderErrorBanner(message: error) { Task { await loadPermissions() } } }
            if let error = listing.error { OrderErrorBanner(message: error) { listing.reload() } }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.fixedSize(horizontal: false, vertical: true)
        }
        .searchable(text: $search, prompt: "Search orders")
        .task(id: search) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard search != listing.term else { return }
                selection = []; listing.setTerm(search); listing.search()
            } catch { }
        }
        .task { await loadPermissions() }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: sorting) { applySorting() }
        .onChange(of: listing.activeValues) { selection = [] }
        .onChange(of: orderID) { previous, current in
            if previous != nil && current == nil {
                selection = []
                listing.reload()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create order", systemImage: "plus") { creating = true }
                    .disabled(!permissions.allows("order:create") || !permissions.allows("customer:read") || !permissions.allows("api_proxy_switch-customer"))
                    .help("Create order").accessibilityIdentifier("orders.create")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { filters = true } label: { Label("Filters", systemImage: listing.activeFilterCount == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }
                    .badge(listing.activeFilterCount).accessibilityIdentifier("orders.filters")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !useTable { Button(selecting ? "Done selecting" : "Select orders") { selecting.toggle(); selection = [] } }
                    Button("Select loaded orders") { selection = Set(listing.items.map(\.id)); selecting = true }
                    Button("Clear selection") { selection = [] }.disabled(selection.isEmpty)
                    Divider()
                    Button("Change selected statuses…") { bulk = .status }.disabled(selection.isEmpty || !permissions.allows("order:update"))
                    Button("Delete selected orders…", role: .destructive) { bulk = .delete }.disabled(selection.isEmpty || !permissions.allows("order:delete"))
                    Divider()
                    sortMenu
                    Button("Refresh orders", systemImage: "arrow.clockwise") { listing.reload() }.disabled(listing.loading)
                } label: { Label("Order list actions", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("orders.actions")
            }
        }
        .sheet(isPresented: $filters) { FilterSheet(state: listing, api: api) }
        .sheet(isPresented: $creating) {
            OrderCreateCustomerSheet(api: api, shop: shop) { id in listing.reload(); orderID = id }
        }
        .sheet(item: $bulk) { action in
            OrderBulkSheet(api: api, action: action, orders: listing.items.filter { selection.contains($0.id) }) { succeeded in
                selection.subtract(succeeded); listing.reload()
            }
        }
        .navigationDestination(item: $orderID) { OrderDetailView(shop: shop, orderId: $0) }
        .accessibilityIdentifier("orders.workspace")
    }

    @ViewBuilder private var content: some View {
        if listing.items.isEmpty && listing.loading { ProgressView("Loading orders…") }
        else if listing.items.isEmpty && listing.error == nil {
            ContentUnavailableView {
                Label(listing.term.isEmpty && listing.activeFilterCount == 0 ? "No orders yet" : "No matching orders", systemImage: "doc.text")
            } description: { Text("Orders from your shop will appear here.") }
            actions: {
                if listing.activeFilterCount > 0 { Button("Clear filters") { listing.applyFilterValues([:]) } }
            }
        } else if useTable { table }
        else {
            List(listing.items) { order in
                Button {
                    if selecting { if !selection.insert(order.id).inserted { selection.remove(order.id) } }
                    else { orderID = order.id }
                } label: {
                    HStack(alignment: .top) {
                        if selecting { Image(systemName: selection.contains(order.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
                        OrderListRow(shop: shop, order: order)
                    }.contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("orders.row.\(order.id)")
            }.refreshable { listing.reload(); await listing.fetchTask?.value }
        }
    }

    private var table: some View {
        Table(listing.items, selection: $selection, sortOrder: $sorting) {
            TableColumn("Order", value: \.orderNumber) { Text("#\($0.orderNumber)").monospacedDigit() }.width(min: 85, ideal: 100)
            TableColumn("Customer", value: \.customer) { order in
                VStack(alignment: .leading) {
                    Text(order.customer)
                    if let company = order.company, !company.isEmpty { Text(company).font(.caption).foregroundStyle(.secondary) }
                }
            }.width(min: 140, ideal: 190)
            TableColumn("Date", value: \.placedMs) { Text(Date(timeIntervalSince1970: Double($0.placedMs) / 1000), format: .dateTime.day().month().year()) }.width(min: 90, ideal: 100)
            TableColumn("Sales channel") { Text($0.salesChannel ?? "—") }.width(min: 90, ideal: 115)
            TableColumn("Total", value: \.amount) { Text(shop.fmt($0.amount, iso: $0.currencyIso)).monospacedDigit() }.width(min: 90, ideal: 110)
            TableColumn("Order status", value: \.state) { StatusBadge(label: $0.state, tone: stateTone($0.stateTechnical)) }.width(min: 90, ideal: 110)
            TableColumn("Payment") { StatusBadge(label: $0.paymentState ?? "—", tone: stateTone($0.paymentStateTechnical ?? "")) }.width(min: 85, ideal: 110)
            TableColumn("Delivery") { StatusBadge(label: $0.deliveryState ?? "—", tone: stateTone($0.deliveryStateTechnical ?? "")) }.width(min: 85, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first { Button("Open order") { orderID = id } }
            Button("Change selected statuses…") { selection = ids; bulk = .status }.disabled(ids.isEmpty || !permissions.allows("order:update"))
            Button("Delete selected orders…", role: .destructive) { selection = ids; bulk = .delete }.disabled(ids.isEmpty || !permissions.allows("order:delete"))
        } primaryAction: { ids in if ids.count == 1 { orderID = ids.first } }
    }

    private var footer: some View {
        HStack {
            if listing.loading { ProgressView().controlSize(.small) }
            Text(selection.isEmpty ? String(localized: "\(listing.total) orders") : String(localized: "\(selection.count) selected"))
                .foregroundStyle(.secondary).font(.callout)
            Spacer()
            if listing.items.count < listing.total { Button("Load more") { listing.loadMore() }.disabled(listing.loading).accessibilityIdentifier("orders.loadMore") }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var sortMenu: some View {
        Menu("Sort orders") {
            Button("Newest first") { sorting = [KeyPathComparator(\RecentOrder.placedMs, order: .reverse)] }
            Button("Oldest first") { sorting = [KeyPathComparator(\RecentOrder.placedMs)] }
            Button("Order number") { sorting = [KeyPathComparator(\RecentOrder.orderNumber)] }
            Button("Highest total") { sorting = [KeyPathComparator(\RecentOrder.amount, order: .reverse)] }
            Button("Customer name") { sorting = [KeyPathComparator(\RecentOrder.customer)] }
        }
    }
    private func applySorting() {
        selection = []
        var fields = sorting.compactMap { comparator -> ListingSort? in
            let field: String
            switch comparator.keyPath {
            case \RecentOrder.placedMs: field = "orderDateTime"
            case \RecentOrder.orderNumber: field = "orderNumber"
            case \RecentOrder.customer: field = "orderCustomer.lastName"
            case \RecentOrder.amount: field = "amountTotal"
            case \RecentOrder.state: field = "stateMachineState.name"
            default: return nil
            }
            return ListingSort(field: field, ascending: comparator.order == .forward, natural: field == "orderNumber")
        }
        fields.append(ListingSort(field: "id")); listing.setSorting(fields)
    }
    private func loadPermissions() async {
        do { permissions = try await api.permissions(); permissionError = nil }
        catch { permissionError = (error as? ApiError)?.message ?? error.localizedDescription; permissions = AdminPermissions() }
    }
}

private struct OrderListRow: View {
    let shop: ConnectedShop
    let order: RecentOrder
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
            layout {
                Text("#\(order.orderNumber)").fontWeight(.semibold).monospacedDigit()
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(shop.fmt(order.amount, iso: order.currencyIso)).fontWeight(.semibold).monospacedDigit()
            }
            Text(order.customer)
            if let company = order.company, !company.isEmpty { Text(company).font(.callout).foregroundStyle(.secondary) }
            Text(Date(timeIntervalSince1970: Double(order.placedMs) / 1000), format: .dateTime.day().month().year()).font(.callout).foregroundStyle(.secondary)
            if let channel = order.salesChannel { Text(channel).font(.caption).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { statuses }
                VStack(alignment: .leading, spacing: 8) { statuses }
            }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
    @ViewBuilder private var statuses: some View {
        StatusBadge(label: order.state, tone: stateTone(order.stateTechnical)).accessibilityLabel("Order: \(order.state)")
        if let payment = order.paymentState { Label(payment, systemImage: "creditcard").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Payment: \(payment)") }
        if let delivery = order.deliveryState { Label(delivery, systemImage: "shippingbox").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Delivery: \(delivery)") }
    }
}

private struct OrderCreateCustomerSheet: View {
    let api: ShopApi
    let shop: ConnectedShop
    let created: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customer: CustomerDetail?
    @State private var selecting = true
    @State private var loading = false
    @State private var error: String?
    @State private var customerID: String?
    var body: some View {
        Group {
            if let customer {
                CustomerOrderCreateSheet(api: api, shop: shop, customer: customer, onCreated: created)
            } else {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Choose a customer", systemImage: "person.crop.circle")
                    } description: { Text(error ?? String(localized: "Select the customer who will receive this order.")) }
                    actions: {
                        if loading { ProgressView() }
                        else {
                            Button("Choose customer…") { selecting = true }
                            if customerID != nil { Button("Retry") { Task { await loadCustomer() } } }
                        }
                    }.navigationTitle("Create order")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
                #if os(macOS)
                .frame(width: 520, height: 360)
                #endif
            }
        }
        .sheet(isPresented: $selecting) {
            CustomerEntitySelectionSheet(api: api, entity: "customer", title: String(localized: "Choose a customer"), multiple: false, selected: []) {
                customerID = $0.first; Task { await loadCustomer() }
            }
        }
    }
    private func loadCustomer() async {
        guard let customerID else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            guard let result = try await api.fetchCustomerDetail(customerID) else { throw ApiError.notFound(message: String(localized: "Customer not found")) }
            customer = result
        } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }
}
