#if os(macOS)
import SwiftUI
import ShopwareAdminAPI

struct MacCustomersTable: View {
    @Bindable var vm: CustomersViewModel
    let shop: ConnectedShop
    @Bindable var listing: ListingState<CustomerRow>
    let onOpen: (String) -> Void
    @State private var sortOrder = [KeyPathComparator(\CustomerRow.createdAt, order: .reverse)]
    @SceneStorage("customers.columns") private var columnCustomization: TableColumnCustomization<CustomerRow>
    @State private var search = ""
    @State private var filters = false

    @State private var actions = CustomerListActions()

    var body: some View {
        VStack(spacing: 0) {
            if let permissionsError = vm.permissionsError {
                HStack {
                    Text(permissionsError).foregroundStyle(.secondary)
                    Button("Retry") { Task { await vm.loadPermissions() } }
                }.padding()
            }
            if let error = listing.error {
                HStack {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { listing.reload() }
                }.padding()
            }
            if listing.items.isEmpty && !listing.loading && listing.error == nil {
                ContentUnavailableView("No customers found", systemImage: "person.2",
                                       description: Text("Try another search or adjust your filters."))
            } else {
                customerTable
            }
            Divider()
            HStack {
                if listing.loading || actions.busy { ProgressView().controlSize(.small) }
                Text("Showing \(listing.items.count) of \(listing.total) customers").foregroundStyle(.secondary)
                if !actions.selection.isEmpty { Text("\(actions.selection.count) selected").foregroundStyle(.secondary) }
                Spacer()
                if listing.items.count < listing.total {
                    Button("Load more") { listing.loadMore() }.disabled(listing.loading || actions.busy)
                }
            }.padding()
        }
        .searchable(text: $search, prompt: "Search name, email, company or customer number")
        .onSubmit(of: .search) { listing.setTerm(search); listing.search(); actions.selection.removeAll() }
        .onChange(of: search) {
            if search.isEmpty { listing.setTerm(""); listing.search(); actions.selection.removeAll() }
        }
        .onChange(of: sortOrder, applySort)
        .onChange(of: listing.items.map(\.id)) { actions.reconcile(with: listing) }
        .onChange(of: listing.activeValues) { actions.selection.removeAll() }
        .toolbar {
            if !actions.selection.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit selected", systemImage: "pencil") {
                        actions.edit(actions.selection, in: listing)
                    }.disabled(!vm.permissions.allows("customer:update") || actions.busy)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add customer", systemImage: "plus") { actions.creating = true }
                    .disabled(!vm.permissions.allows("customer:create") || actions.busy)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { listing.reload() }
                    .disabled(listing.loading || actions.busy)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Filters", systemImage: listing.activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                    filters = true
                }.badge(listing.activeFilterCount)
            }
        }
        .sheet(isPresented: $filters) { FilterSheet(state: listing, api: vm.api) }
        .modifier(CustomerListSheets(actions: actions, vm: vm, listing: listing, onOpen: onOpen))
    }

    private var customerTable: some View {
        Table(listing.items, selection: $actions.selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Customer", value: \.name) { customer in
                VStack(alignment: .leading, spacing: 3) {
                    Text(customer.name).bold().lineLimit(1)
                    Text(customer.email).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.vertical, 4)
            }.width(min: 180, ideal: 240).customizationID("identity").disabledCustomizationBehavior(.visibility)
            TableColumn("Customer no.", value: \.customerNumber).width(min: 90, ideal: 120).customizationID("number")
            TableColumn("Group", value: \.group) { customer in
                VStack(alignment: .leading) {
                    Text(customer.group)
                    if let group = customer.requestedGroup {
                        Label("Requested: \(group)", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.width(min: 100, ideal: 150).customizationID("group")
            TableColumn("City", value: \.city).width(min: 90, ideal: 130).customizationID("city")
            TableColumn("Registered", value: \.createdAt) { customer in
                if customer.createdAt != .distantPast { Text(customer.createdAt, format: .dateTime.day().month().year()) }
            }.width(min: 100, ideal: 120).customizationID("createdAt")
            optionalColumns
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first { Button("Open customer") { onOpen(id) } }
            if !ids.isEmpty {
                Button("Edit selected customers") {
                    actions.edit(ids, in: listing)
                }.disabled(!vm.permissions.allows("customer:update") || actions.busy)
                Button("Delete selected customers", role: .destructive) { actions.deleteIDs = ids.sorted() }
                    .disabled(!vm.permissions.allows("customer:delete") || actions.busy)
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { onOpen(id) }
        }
    }

    @TableColumnBuilder<CustomerRow, KeyPathComparator<CustomerRow>>
    private var optionalColumns: some TableColumnContent<CustomerRow, KeyPathComparator<CustomerRow>> {
            TableColumn("Company", value: \.company).customizationID("company").defaultVisibility(.hidden)
            TableColumn("Street", value: \.street).customizationID("street").defaultVisibility(.hidden)
            TableColumn("Postal code", value: \.zipcode).customizationID("zipcode").defaultVisibility(.hidden)
            TableColumn("Bound sales channel", value: \.boundSalesChannel).customizationID("boundSalesChannel").defaultVisibility(.hidden)
            TableColumn("Status") { customer in
                StatusBadge(label: String(localized: customer.active ? "Active" : "Disabled"), tone: customer.active ? .done : .error)
            }.customizationID("status").defaultVisibility(.hidden)
            TableColumn("Registration") { Text($0.guest ? "Guest" : "Registered") }.customizationID("guest").defaultVisibility(.hidden)
            TableColumn("Orders", value: \.orderCount) { Text("\($0.orderCount)").monospacedDigit() }.customizationID("orders").defaultVisibility(.hidden)
            TableColumn("Total spend", value: \.totalSpend) { Text(shop.fmt($0.totalSpend)).monospacedDigit() }.customizationID("spend").defaultVisibility(.hidden)
            TableColumn("Affiliate code", value: \.affiliateCode).customizationID("affiliate").defaultVisibility(.hidden)
            TableColumn("Campaign code", value: \.campaignCode).customizationID("campaign").defaultVisibility(.hidden)
    }

    private func applySort() {
        guard let sort = sortOrder.first else { return }
        let ascending = sort.order == .forward
        let fields: [String]
        switch sort.keyPath {
        case \CustomerRow.name: fields = ["lastName", "firstName"]
        case \CustomerRow.customerNumber: fields = ["customerNumber"]
        case \CustomerRow.group: fields = ["group.name"]
        case \CustomerRow.city: fields = ["defaultBillingAddress.city"]
        case \CustomerRow.street: fields = ["defaultBillingAddress.street"]
        case \CustomerRow.zipcode: fields = ["defaultBillingAddress.zipcode"]
        case \CustomerRow.company: fields = ["company"]
        case \CustomerRow.boundSalesChannel: fields = ["boundSalesChannel.name"]
        case \CustomerRow.orderCount: fields = ["orderCount"]
        case \CustomerRow.totalSpend: fields = ["orderTotalAmount"]
        case \CustomerRow.affiliateCode: fields = ["affiliateCode"]
        case \CustomerRow.campaignCode: fields = ["campaignCode"]
        default: fields = ["createdAt"]
        }
        listing.setSorting(fields.map { ListingSort(field: $0, ascending: ascending, natural: $0 == "customerNumber") }
                           + [ListingSort(field: "id")])
        actions.selection.removeAll()
    }

}
#endif
