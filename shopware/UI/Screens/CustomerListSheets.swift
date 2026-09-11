import SwiftUI

/// Both listing presentations use the same create, bulk-edit and delete flow.
struct CustomerListSheets: ViewModifier {
    @Bindable var actions: CustomerListActions
    let vm: CustomersViewModel
    let listing: ListingState<CustomerRow>
    let onOpen: (String) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $actions.creating) {
                if let api = vm.api {
                    CustomerCreateSheet(api: api, permissions: vm.permissions) { id in
                        listing.reload()
                        onOpen(id)
                    }
                }
            }
            .sheet(isPresented: $actions.bulkEditing) {
                if let api = vm.api {
                    CustomerBulkEditSheet(api: api, customers: actions.bulkCustomers, permissions: vm.permissions) { listing.reload() }
                }
            }
            .alert("Delete \(actions.deleteIDs.count) customers?", isPresented: Binding(
                get: { !actions.deleteIDs.isEmpty }, set: { if !$0 { actions.deleteIDs = [] } }
            )) {
                Button("Cancel", role: .cancel) { actions.deleteIDs = [] }
                Button("Delete customers", role: .destructive) { actions.deleteCustomers(vm: vm, listing: listing) }
            } message: { Text("The selected customer accounts will be permanently deleted.") }
            .alert("Customer action failed", isPresented: Binding(
                get: { actions.error != nil }, set: { if !$0 { actions.error = nil } }
            )) {} message: { Text(actions.error ?? "") }
    }
}
