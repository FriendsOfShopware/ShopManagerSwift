import SwiftUI
import ShopwareAdminAPI

struct CustomerGroupRequestBanner: View {
    let vm: CustomerDetailViewModel
    let groupName: String
    let onSaved: () -> Void
    @State private var accepting: Bool?

    var body: some View {
        GroupBox {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    message
                    Spacer()
                    actions
                }
                VStack(alignment: .leading, spacing: 12) {
                    message
                    actions.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(8)
            .disabled(vm.busy || !vm.permissions.allows("customer:update"))
        }
        .padding()
        .confirmationDialog(accepting == true ? "Approve group request?" : "Decline group request?", isPresented: Binding(
            get: { accepting != nil }, set: { if !$0 { accepting = nil } }
        ), titleVisibility: .visible) {
            Button(accepting == true ? "Approve" : "Decline", action: decide)
        } message: { Text("Shopware will process the request and run its configured notifications.") }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Customer requested access to \(groupName)", systemImage: "person.badge.clock").bold()
            if vm.detail?.active == false {
                Text("This customer is inactive. Approving the group request does not activate the account.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Decline", role: .destructive) { accepting = false }
            Button("Approve") { accepting = true }.buttonStyle(.borderedProminent)
        }
        #if os(iOS)
        .controlSize(.large)
        #endif
    }

    private func decide() {
        guard let accept = accepting else { return }
        accepting = nil
        Task {
            if await vm.perform({ try await vm.api.customers.decideGroupRequest(customerIds: [vm.customerId], accept: accept) }) { onSaved() }
        }
    }
}
