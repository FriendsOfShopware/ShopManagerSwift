import SwiftUI
import ShopwareAdminAPI

struct CustomerActionsMenu: View {
    @Environment(\.dismiss) private var dismiss
    let vm: CustomerDetailViewModel
    let onSaved: () -> Void
    @State private var converting = false
    @State private var loggingIn = false
    @State private var deleting = false

    var body: some View {
        Menu("Customer actions", systemImage: "ellipsis") {
            if vm.detail?.guest == true {
                Button("Convert to registered customer") { converting = true }
                    .disabled(!vm.permissions.allows("customer:update"))
            }
            #if os(macOS) || os(iOS)
            Button("Log in as customer", systemImage: "person.crop.circle.badge.checkmark") { loggingIn = true }
                .disabled(vm.detail?.guest != false || vm.detail?.active != true || vm.permissions.userId == nil || !vm.permissions.allows("api_proxy_imitate-customer"))
            #endif
            Divider()
            Button("Delete customer", role: .destructive) { deleting = true }
                .disabled(!vm.permissions.allows("customer:delete"))
        }
        .disabled(vm.busy)
        // macOS 26 otherwise exposes the ellipsis symbol as the generic "More".
        .accessibilityLabel("Customer actions")
        .sheet(isPresented: $converting) { CustomerConvertGuestSheet(vm: vm, onSaved: onSaved) }
        #if os(macOS) || os(iOS)
        .sheet(isPresented: $loggingIn) { CustomerLoginSheet(vm: vm) }
        #endif
        .confirmationDialog("Delete this customer?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete customer", role: .destructive, action: deleteCustomer)
                .accessibilityIdentifier("customer.delete.confirm")
        } message: { Text("The customer account will be permanently deleted.") }
    }

    private func deleteCustomer() {
        Task {
            if await vm.perform({ try await vm.api.repository("customer").delete(vm.customerId) }) {
                onSaved()
                dismiss()
            }
        }
    }
}
