import SwiftUI
import ShopwareAdminAPI

struct CustomerAddressesView: View {
    @Bindable var vm: CustomerDetailViewModel
    let onSaved: () -> Void
    @State private var search = ""
    @State private var edit: CustomerAddressEdit?
    @State private var deleting: EditableAddress?
    @State private var sortField = "lastName"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search addresses", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vm.addresses.setTerm(search); vm.addresses.search() }
                    .onChange(of: search) {
                        if search.isEmpty { vm.addresses.setTerm(""); vm.addresses.search() }
                    }
                HStack {
                Button("Add address", systemImage: "plus", action: addAddress)
                    .disabled(!vm.permissions.allows("customer_address:create") || !vm.permissions.allows("customer:update") || vm.busy)
                Spacer()
                Menu("Sort addresses", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort by", selection: $sortField) {
                        Text("Name").tag("lastName")
                        Text("Company").tag("company")
                        Text("City").tag("city")
                        Text("Postal code").tag("zipcode")
                        Text("Newest first").tag("createdAt")
                    }
                }
                }
                #if os(iOS)
                .frame(minHeight: 44)
                #endif
            }
            .padding()
            List {
                if let error = vm.addresses.error {
                    HStack {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { vm.addresses.reload() }
                    }
                }
                if vm.addresses.items.isEmpty && !vm.addresses.loading && vm.addresses.error == nil {
                    ContentUnavailableView("No addresses found", systemImage: "house",
                                           description: Text(search.isEmpty ? "Add an address for this customer." : "Try a different search."))
                }
                ForEach(vm.addresses.items) { address in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(address.formatted).textSelection(.enabled)
                            VStack(alignment: .leading, spacing: 4) {
                                if vm.detail?.defaultBillingAddressId == address.id {
                                    Label("Default billing", systemImage: "creditcard")
                                }
                                if vm.detail?.defaultShippingAddressId == address.id {
                                    Label("Default shipping", systemImage: "shippingbox")
                                }
                            }.foregroundStyle(.secondary)
                            if let phone = address.phoneNumber, !phone.isEmpty {
                                Label(phone, systemImage: "phone").textSelection(.enabled)
                            }
                            if !address.customFields.isEmpty, !vm.addressCustomFieldSets.isEmpty {
                                DisclosureGroup("Custom fields") {
                                    CustomerCustomFieldsSummary(sets: vm.addressCustomFieldSets, values: address.customFields, api: vm.api)
                                }
                            }
                        }
                        Spacer()
                        Menu("Address actions", systemImage: "ellipsis") {
                            Button("Edit", systemImage: "pencil") { edit = CustomerAddressEdit(address: address, isNew: false) }
                                .disabled(!vm.permissions.allows("customer_address:update") || !vm.permissions.allows("customer:update"))
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                var copy = address
                                copy.id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                                edit = CustomerAddressEdit(address: copy, isNew: true)
                            }.disabled(!vm.permissions.allows("customer_address:create") || !vm.permissions.allows("customer:update"))
                            Button("Use as default billing") { setDefault(address.id, billing: true) }
                                .disabled(!vm.permissions.allows("customer:update") || vm.detail?.defaultBillingAddressId == address.id)
                            Button("Use as default shipping") { setDefault(address.id, billing: false) }
                                .disabled(!vm.permissions.allows("customer:update") || vm.detail?.defaultShippingAddressId == address.id)
                            Divider()
                            Button("Delete address", role: .destructive) { deleting = address }
                                .disabled(!vm.permissions.allows("customer_address:delete") || vm.isDefaultAddress(address.id))
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(vm.busy)
                    }.padding(.vertical, 8)
                }
            }
            .groupedListStyle()
            .refreshable { vm.addresses.reload(); await vm.addresses.fetchTask?.value }
            HStack {
                if vm.addresses.loading { ProgressView().controlSize(.small) }
                Text("Showing \(vm.addresses.items.count) of \(vm.addresses.total) addresses").foregroundStyle(.secondary)
                Spacer()
                if vm.addresses.items.count < vm.addresses.total {
                    Button("Load more") { vm.addresses.loadMore() }.disabled(vm.addresses.loading)
                }
            }.padding()
        }
        .task { if vm.addresses.items.isEmpty { vm.addresses.reload() } }
        .onChange(of: sortField) {
            vm.addresses.setSorting([ListingSort(field: sortField, ascending: sortField != "createdAt"), ListingSort(field: "id")])
        }
        .sheet(item: $edit) { request in CustomerAddressSheet(vm: vm, request: request, onSaved: onSaved) }
        .alert("Delete address?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive, action: deleteAddress)
        } message: { Text(deleting?.formatted ?? "") }
    }

    private func addAddress() {
        edit = CustomerAddressEdit(address: EditableAddress(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            firstName: vm.detail?.firstName ?? "", lastName: vm.detail?.lastName ?? "",
            company: vm.detail?.company, salutationId: vm.detail?.salutationId
        ), isNew: true)
    }

    private func setDefault(_ id: String, billing: Bool) {
        Task {
            if await vm.perform({
                try await vm.api.repository("customer").patch(vm.customerId, .object([
                    billing ? "defaultBillingAddressId" : "defaultShippingAddressId": .string(id),
                ]))
            }) { onSaved() }
        }
    }

    private func deleteAddress() {
        guard let address = deleting, !vm.isDefaultAddress(address.id) else { return }
        deleting = nil
        Task {
            if await vm.perform({ try await vm.api.repository("customer-address").delete(address.id) }) { onSaved() }
        }
    }
}
