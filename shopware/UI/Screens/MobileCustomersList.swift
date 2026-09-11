#if os(iOS)
import SwiftUI
import ShopwareAdminAPI

struct MobileCustomersList: View {
    @Bindable var vm: CustomersViewModel
    let shop: ConnectedShop
    @Bindable var listing: ListingState<CustomerRow>
    let onOpen: (String) -> Void
    @State private var editMode: EditMode = .inactive
    @State private var search = ""
    @State private var sortField = "createdAt"
    @State private var ascending = false
    @State private var filters = false

    @State private var actions = CustomerListActions()

    var body: some View {
        List(selection: $actions.selection) {
            if let message = vm.permissionsError {
                Section {
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry permissions") { Task { await vm.loadPermissions() } }
                }
            }
            if let error = listing.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Button("Retry") { listing.reload() }
                }
            }
            Section {
                ForEach(listing.items) { customer in
                    Group {
                        if editMode.isEditing {
                            MobileCustomerRow(shop: shop, customer: customer)
                        } else {
                            NavigationLink(value: CustomerRoute(id: customer.id)) {
                                MobileCustomerRow(shop: shop, customer: customer)
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                if vm.permissions.allows("customer:delete") && !actions.busy {
                                    Button("Delete", role: .destructive) { actions.deleteIDs = [customer.id] }
                                }
                            }
                        }
                    }
                    .tag(customer.id)
                }
                if listing.loading {
                    ProgressView("Loading customers…").frame(maxWidth: .infinity)
                } else if listing.items.count < listing.total {
                    Button("Load more customers") { listing.loadMore() }.frame(maxWidth: .infinity)
                }
            } header: {
                Text("^[\(listing.total) customer](inflect: true)")
            } footer: {
                if !listing.items.isEmpty { Text("Showing \(listing.items.count) of \(listing.total) customers") }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .overlay {
            if listing.items.isEmpty && !listing.loading && listing.error == nil && vm.permissionsError == nil {
                ContentUnavailableView("No customers found", systemImage: "person.2",
                                       description: Text("Try another search, adjust your filters, or add a customer."))
            }
        }
        .searchable(text: $search, prompt: "Name, email, company or number")
        .onSubmit(of: .search, submitSearch)
        .onChange(of: search) { if search.isEmpty { submitSearch() } }
        .onChange(of: sortField, applySort)
        .onChange(of: ascending, applySort)
        .onChange(of: listing.activeValues) { actions.selection.removeAll() }
        .onChange(of: listing.items.map(\.id)) { actions.reconcile(with: listing) }
        .refreshable {
            listing.reload()
            await listing.fetchTask?.value
            await vm.loadPermissions()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add customer", systemImage: "plus") { actions.creating = true }
                    .disabled(!vm.permissions.allows("customer:create") || actions.busy || editMode.isEditing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Customer list options", systemImage: "ellipsis.circle") {
                    Button("Filters", systemImage: "line.3.horizontal.decrease.circle") { filters = true }
                    Menu("Sort customers", systemImage: "arrow.up.arrow.down") {
                        Picker("Sort by", selection: $sortField) {
                            Text("Registered").tag("createdAt")
                            Text("Name").tag("lastName")
                            Text("Customer number").tag("customerNumber")
                            Text("Group").tag("group.name")
                            Text("Company").tag("company")
                            Text("City").tag("defaultBillingAddress.city")
                            Text("Street").tag("defaultBillingAddress.street")
                            Text("Postal code").tag("defaultBillingAddress.zipcode")
                            Text("Bound sales channel").tag("boundSalesChannel.name")
                            Text("Orders").tag("orderCount")
                            Text("Total spend").tag("orderTotalAmount")
                            Text("Affiliate code").tag("affiliateCode")
                            Text("Campaign code").tag("campaignCode")
                        }
                        Picker("Direction", selection: $ascending) {
                            Text("Ascending").tag(true)
                            Text("Descending").tag(false)
                        }
                    }
                    Button(editMode.isEditing ? "Done selecting" : "Select customers", systemImage: "checkmark.circle") {
                        editMode = editMode.isEditing ? .inactive : .active
                        actions.selection.removeAll()
                    }.disabled(listing.items.isEmpty || actions.busy)
                    if editMode.isEditing {
                        Button("Select all shown") { actions.selection = Set(listing.items.map(\.id)) }
                        Button("Deselect all") { actions.selection.removeAll() }
                    }
                }.badge(listing.activeFilterCount)
            }
            if editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Edit selected", systemImage: "pencil") {
                        actions.edit(actions.selection, in: listing)
                    }.disabled(actions.selection.isEmpty || !vm.permissions.allows("customer:update") || actions.busy)
                    Spacer()
                    Text("\(actions.selection.count) selected").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete selected", systemImage: "trash", role: .destructive) { actions.deleteIDs = actions.selection.sorted() }
                        .disabled(actions.selection.isEmpty || !vm.permissions.allows("customer:delete") || actions.busy)
                }
            }
        }
        .sheet(isPresented: $filters) { FilterSheet(state: listing, api: vm.api) }
        .modifier(CustomerListSheets(actions: actions, vm: vm, listing: listing, onOpen: onOpen))
    }

    private func submitSearch() {
        actions.selection.removeAll()
        listing.setTerm(search)
        listing.search()
    }

    private func applySort() {
        actions.selection.removeAll()
        var fields = [ListingSort(field: sortField, ascending: ascending, natural: sortField == "customerNumber")]
        if sortField == "lastName" { fields.append(ListingSort(field: "firstName", ascending: ascending)) }
        fields.append(ListingSort(field: "id"))
        listing.setSorting(fields)
    }

}
#endif
