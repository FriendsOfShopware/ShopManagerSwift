import SwiftUI

struct CustomerOrderHistory: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let shop: ConnectedShop
    @Bindable var orders: ListingState<RecentOrder>
    let canCreateOrder: Bool
    let onCreateOrder: () -> Void
    @State private var selection: RecentOrder.ID?
    @State private var orderId: String?
    @State private var search = ""
    #if os(macOS)
    @State private var sortOrder = [KeyPathComparator(\RecentOrder.placedMs, order: .reverse)]
    #else
    @State private var sortField = "orderDateTime"
    @State private var ascending = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if orders.items.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(macOS)
                Table(orders.items, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Order", value: \.orderNumber) { order in
                        Button("#\(order.orderNumber)") { orderId = order.id }
                            .buttonStyle(.link)
                            .monospacedDigit()
                            .help("Open order #\(order.orderNumber)")
                    }
                    TableColumn("Date", value: \.placedMs) { order in
                        Text(Date(timeIntervalSince1970: Double(order.placedMs) / 1000), format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Status", value: \.state) { order in
                        StatusBadge(label: order.state, tone: stateTone(order.stateTechnical))
                    }
                    TableColumn("Total", value: \.amount) { order in
                        Text(shop.fmt(order.amount, iso: order.currencyIso)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxHeight: .infinity)
                .contextMenu(forSelectionType: RecentOrder.ID.self) { ids in
                    if let id = ids.first {
                        Button("Open order", systemImage: "doc.text") { orderId = id }
                    }
                } primaryAction: { ids in
                    orderId = ids.first
                }

                #else
                List(orders.items) { order in
                    Button { orderId = order.id } label: { OrderRow(shop: shop, order: order, showsCustomer: false) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open order")
                }
                .listStyle(.insetGrouped)
                .refreshable { orders.reload(); await orders.fetchTask?.value }
                #endif

                Divider()
                HStack {
                    if orders.loading { ProgressView().controlSize(.small) }
                    if let error = orders.error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Showing \(orders.items.count) of \(orders.total)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if orders.items.count < orders.total {
                        Button(orders.error == nil ? "Load more" : "Retry") { orders.loadMore() }
                            .disabled(orders.loading)
                    }
                }.padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(macOS)
        .onChange(of: sortOrder) {
            guard let sort = sortOrder.first else { return }
            let field: String
            switch sort.keyPath {
            case \RecentOrder.orderNumber: field = "orderNumber"
            case \RecentOrder.amount: field = "amountTotal"
            case \RecentOrder.state: field = "stateMachineState.name"
            default: field = "orderDateTime"
            }
            orders.setSorting([ListingSort(field: field, ascending: sort.order == .forward, natural: field == "orderNumber"), ListingSort(field: "id")])
        }
        #else
        .onChange(of: sortField, applyMobileSort)
        .onChange(of: ascending, applyMobileSort)
        #endif
        .navigationDestination(item: $orderId) { id in
            OrderDetailView(shop: shop, orderId: id)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
            headerLayout {
                Text("Order history").font(.headline)
                #if os(macOS)
                if orders.total > 0 {
                    Text("^[\(orders.total) order](inflect: true)").foregroundStyle(.secondary)
                }
                #endif
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Create order…", systemImage: "plus", action: onCreateOrder)
                    .disabled(!canCreateOrder)
            }
            #if os(iOS)
            Menu("Sort orders", systemImage: "arrow.up.arrow.down") {
                Picker("Sort by", selection: $sortField) {
                    Text("Date").tag("orderDateTime")
                    Text("Order number").tag("orderNumber")
                    Text("Status").tag("stateMachineState.name")
                    Text("Total").tag("amountTotal")
                }
                Picker("Direction", selection: $ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
            }.frame(minHeight: 44)
            #endif
            TextField("Search orders", text: $search)
                .textFieldStyle(.roundedBorder)
                .onSubmit { orders.setTerm(search); orders.search() }
                .onChange(of: search) { if search.isEmpty { orders.setTerm(""); orders.search() } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }

    #if os(iOS)
    private func applyMobileSort() {
        orders.setSorting([ListingSort(field: sortField, ascending: ascending, natural: sortField == "orderNumber"), ListingSort(field: "id")])
    }
    #endif

    @ViewBuilder private var emptyState: some View {
        if orders.loading {
            ProgressView("Loading orders…")
        } else if let error = orders.error {
            ContentUnavailableView {
                Label("Couldn't load orders", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { orders.reload() }
            }
        } else {
            ContentUnavailableView(orders.term.isEmpty ? "No orders yet" : "No matching orders", systemImage: "doc.text",
                                   description: Text(orders.term.isEmpty ? "Orders placed by this customer will appear here." : "Try another order number or search term."))
        }
    }
}
