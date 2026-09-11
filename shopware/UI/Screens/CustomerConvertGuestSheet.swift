import SwiftUI
import ShopwareAdminAPI

struct CustomerConvertGuestSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: CustomerDetailViewModel
    let onSaved: () -> Void
    @State private var sendEmail = true
    @State private var password = ""
    @State private var confirmation = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(vm.detail?.email ?? "")
                    Toggle("Send password setup email", isOn: $sendEmail)
                    if !sendEmail {
                        SecureField("Password", text: $password)
                        SecureField("Confirm password", text: $confirmation)
                    }
                } footer: {
                    Text("The guest becomes a registered customer. When enabled, Shopware sends an email so they can set their password.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .groupedFormStyle().disabled(saving)
            .navigationTitle("Convert guest to customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: convert) {
                        HStack {
                            if saving { ProgressView().controlSize(.small) }
                            Text("Convert")
                        }
                    }.disabled(saving || (!sendEmail && (password.isEmpty || password != confirmation)))
                }
            }
        }
        .interactiveDismissDisabled(saving)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 280, idealHeight: 360)
        #endif
    }

    private func convert() {
        guard !saving, vm.permissions.allows("customer:update") else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await vm.api.customers.convertGuest(customerId: vm.customerId, password: sendEmail ? nil : password)
                await vm.load()
                onSaved()
                dismiss()
            } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
