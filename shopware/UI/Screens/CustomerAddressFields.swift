import SwiftUI

struct CustomerAddressFields: View {
    @Binding var address: EditableAddress
    let countries: [CountryOption]
    let states: [CustomerOption]
    let salutations: [SalutationOption]
    var showRecipient = true

    var body: some View {
        if showRecipient {
          Section("Recipient") {
            Picker("Salutation", selection: $address.salutationId.orEmpty) {
                Text("Not specified").tag("")
                ForEach(salutations) { Text($0.label).tag($0.id) }
            }
            TextField("Title", text: $address.title.orEmpty)
            TextField("First name", text: $address.firstName)
                .textContentType(.givenName)
            TextField("Last name", text: $address.lastName)
                .textContentType(.familyName)
            TextField("Company", text: $address.company.orEmpty)
            TextField("Department", text: $address.department.orEmpty)
          }
        }
        Section("Address") {
            TextField("Street", text: $address.street)
                .accessibilityIdentifier("customer.address.street")
                .textContentType(.streetAddressLine1)
            TextField("Additional address line 1", text: $address.additionalLine.orEmpty)
            TextField("Additional address line 2", text: $address.additionalLine2.orEmpty)
            TextField("Postal code", text: $address.zipcode)
                .accessibilityIdentifier("customer.address.zipcode")
                .textContentType(.postalCode)
            TextField("City", text: $address.city)
                .accessibilityIdentifier("customer.address.city")
            Picker("Country", selection: $address.countryId.orEmpty) {
                Text("Select a country").tag("")
                ForEach(countries) { Text($0.name).tag($0.id) }
            }
            if !states.isEmpty {
                Picker("State / region", selection: $address.countryStateId.orEmpty) {
                    Text("Select a state or region").tag("")
                    ForEach(states) { Text($0.name).tag($0.id) }
                }
            }
            TextField("Phone", text: $address.phoneNumber.orEmpty)
                .textContentType(.telephoneNumber)
                #if os(iOS)
                .keyboardType(.phonePad)
                #endif
        }
    }
}
