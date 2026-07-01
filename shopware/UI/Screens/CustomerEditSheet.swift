import SwiftUI
import ShopwareAdminAPI

/// Edits customer-level contact fields (salutation, name, email, title, company) plus the default
/// billing and shipping addresses. When billing and shipping share one record, only one block
/// shows. Blank optional fields are sent as null to clear them.
struct CustomerEditSheet: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let detail: CustomerDetail
    let onSaved: () -> Void

    // Contact
    @State private var salutationId: String?
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var title = ""
    @State private var company = ""

    // Addresses (edited copies)
    @State private var billing: EditableAddress?
    @State private var shipping: EditableAddress?

    @State private var salutations: [SalutationOption] = []
    @State private var countries: [CountryOption] = []
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    Picker("Salutation", selection: Binding(
                        get: { salutationId ?? "" },
                        set: { salutationId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("—").tag("")
                        ForEach(salutations) { s in Text(s.label).tag(s.id) }
                    }
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                    TextField("Title", text: $title)
                    TextField("Company", text: $company)
                }

                if let billingBinding = bindingFor(\.billing) {
                    AddressEditor(title: detail.sharedAddress ? "Address" : "Billing address",
                                  address: billingBinding, countries: countries)
                }
                if !detail.sharedAddress, let shippingBinding = bindingFor(\.shipping) {
                    AddressEditor(title: "Shipping address", address: shippingBinding, countries: countries)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .groupedFormStyle()
            .navigationTitle("Edit customer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .task { await load() }
        }
        .acceptsFirstMouse()
    }

    private func bindingFor(_ keyPath: WritableKeyPath<CustomerEditSheet, EditableAddress?>) -> Binding<EditableAddress>? {
        // Resolve the @State-backed optional into a non-optional binding when present.
        if keyPath == \.billing, let value = billing {
            return Binding(get: { billing ?? value }, set: { billing = $0 })
        }
        if keyPath == \.shipping, let value = shipping {
            return Binding(get: { shipping ?? value }, set: { shipping = $0 })
        }
        return nil
    }

    private func load() async {
        salutationId = detail.salutationId
        firstName = detail.firstName
        lastName = detail.lastName
        email = detail.email
        title = detail.title ?? ""
        company = detail.company ?? ""
        billing = detail.billing
        shipping = detail.shipping
        async let s = try? model.repo.salutations(shop)
        async let c = try? model.repo.countries(shop)
        salutations = await s ?? []
        countries = await c ?? []
    }

    private func save() async {
        saving = true
        error = nil
        do {
            try await model.repo.saveCustomerContact(
                shop, customerId: detail.id, firstName: firstName, lastName: lastName,
                email: email, salutationId: salutationId,
                title: title.isEmpty ? nil : title, company: company.isEmpty ? nil : company
            )
            if let billing { try await model.repo.saveCustomerAddress(shop, address: billing) }
            if !detail.sharedAddress, let shipping { try await model.repo.saveCustomerAddress(shop, address: shipping) }
            onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

private struct AddressEditor: View {
    let title: LocalizedStringKey
    @Binding var address: EditableAddress
    let countries: [CountryOption]

    var body: some View {
        Section(title) {
            TextField("Street", text: $address.street)
            TextField("Address line 2", text: Binding(
                get: { address.additionalLine ?? "" },
                set: { address.additionalLine = $0.isEmpty ? nil : $0 }
            ))
            TextField("ZIP", text: $address.zipcode)
            TextField("City", text: $address.city)
            TextField("Company", text: Binding(
                get: { address.company ?? "" }, set: { address.company = $0.isEmpty ? nil : $0 }
            ))
            TextField("Phone", text: Binding(
                get: { address.phoneNumber ?? "" }, set: { address.phoneNumber = $0.isEmpty ? nil : $0 }
            ))
            Picker("Country", selection: Binding(
                get: { address.countryId ?? "" },
                set: { address.countryId = $0.isEmpty ? nil : $0 }
            )) {
                Text("—").tag("")
                ForEach(countries) { c in Text(c.name).tag(c.id) }
            }
        }
    }
}
