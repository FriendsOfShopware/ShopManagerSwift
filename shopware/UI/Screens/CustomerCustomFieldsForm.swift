import SwiftUI
import ShopwareAdminAPI

struct CustomerCustomFieldsForm: View {
    let sets: [CustomerCustomFieldSet]
    let api: ShopApi
    @Binding var values: [String: JSONValue]

    var body: some View {
        ForEach(sets) { set in
            Section(set.label) {
                ForEach(set.fields) { field in
                    CustomerCustomFieldInput(field: field, api: api, value: Binding(
                        get: { values[field.name] }, set: { values[field.name] = $0 ?? .null }
                    ))
                    if let error = field.validationError(values[field.name]) { Text(error).foregroundStyle(.red) }
                }
            }
        }
    }
}
