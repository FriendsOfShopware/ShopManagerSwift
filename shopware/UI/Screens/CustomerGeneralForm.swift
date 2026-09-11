import SwiftUI
import ShopwareAdminAPI

struct CustomerGeneralForm: View {
    @Binding var customer: CustomerDetail
    let options: CustomerEditorOptions
    let permissions: AdminPermissions
    let api: ShopApi

    var body: some View {
        Section("Contact") {
            Picker("Account type", selection: $customer.accountType) {
                Text("Private").tag("private")
                Text("Business").tag("business")
            }
            Picker("Salutation", selection: $customer.salutationId.orEmpty) {
                Text("Not specified").tag("")
                ForEach(options.salutations) { Text($0.label).tag($0.id) }
            }
            TextField("Title", text: $customer.title.orEmpty)
            TextField("First name", text: $customer.firstName)
                .accessibilityIdentifier("customer.firstName")
            TextField("Last name", text: $customer.lastName)
                .accessibilityIdentifier("customer.lastName")
            TextField("Email", text: $customer.email)
                .accessibilityIdentifier("customer.email")
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
            TextField("Company", text: $customer.company.orEmpty)
            if customer.accountType == "business" {
                CustomerVATField(values: $customer.vatIds)
            }
        }
        Section("Account") {
            Picker("Customer group", selection: $customer.groupId) {
                Text("Select a group").tag("")
                ForEach(options.groups) { Text($0.name).tag($0.id) }
            }
            Toggle("Active", isOn: $customer.active)
            if customer.doubleOptInRegistration {
                Toggle("Registration confirmed", isOn: Binding(
                    get: { customer.doubleOptInConfirmDate != nil },
                    set: { customer.doubleOptInConfirmDate = $0 ? Date() : nil }
                ))
            }
            Picker("Language", selection: $customer.languageId) {
                Text("Select a language").tag("")
                ForEach(options.languages) { Text($0.name).tag($0.id) }
            }
            TextField("Birthday (YYYY-MM-DD)", text: $customer.birthday.orEmpty)
        }
        Section("Attribution") {
            TextField("Affiliate code", text: $customer.affiliateCode.orEmpty)
            TextField("Campaign code", text: $customer.campaignCode.orEmpty)
        }
        if permissions.allows("tag:read") {
            Section("Tags") {
                CustomerTagsField(tags: $customer.tags, knownTags: options.tags, api: api, canCreate: permissions.allows("tag:create"))
            }
        }
        CustomerCustomFieldsForm(sets: options.customFieldSets, api: api, values: $customer.customFields)
    }
}
