import Foundation
import ShopwareAdminAPI

func customerAddressSavePayload(customerId: String, address: EditableAddress, defaultBilling: Bool, defaultShipping: Bool,
                                original: EditableAddress? = nil) -> JSONValue {
    var addressFields = address.payload.objectValue ?? [:]
    if let original {
        addressFields = addressFields.filter { $0.key == "id" || original.payload[$0.key] != $0.value }
        if addressFields["customFields"] != nil {
            addressFields["customFields"] = .object(address.customFields.filter { original.customFields[$0.key] != $0.value })
        }
    }
    var payload: [String: JSONValue] = ["id": .string(customerId), "addresses": .array([.object(addressFields)])]
    if defaultBilling { payload["defaultBillingAddressId"] = .string(address.id) }
    if defaultShipping { payload["defaultShippingAddressId"] = .string(address.id) }
    return .object(payload)
}

extension EditableAddress {
    var payload: JSONValue {
        .object([
            "id": .string(id), "firstName": .string(firstName), "lastName": .string(lastName),
            "street": .string(street), "zipcode": .string(zipcode), "city": .string(city),
            "countryId": nullableField(countryId), "countryStateId": nullableField(countryStateId),
            "salutationId": nullableField(salutationId), "title": nullableField(title),
            "company": nullableField(company), "department": nullableField(department),
            "additionalAddressLine1": nullableField(additionalLine),
            "additionalAddressLine2": nullableField(additionalLine2), "phoneNumber": nullableField(phoneNumber),
            "customFields": .object(customFields),
        ])
    }

    func validationError(country: CountryOption?, business: Bool) -> String? {
        if firstName.trimmed.isEmpty || lastName.trimmed.isEmpty { return String(localized: "Enter the address recipient's first and last name.") }
        if business && (company ?? "").trimmed.isEmpty { return String(localized: "Enter a company for this business address.") }
        if street.trimmed.isEmpty || city.trimmed.isEmpty { return String(localized: "Street and city are required.") }
        if (countryId ?? "").isEmpty { return String(localized: "Select a country.") }
        if country?.postalCodeRequired == true && zipcode.trimmed.isEmpty { return String(localized: "A postal code is required for this country.") }
        if country?.forceStateInRegistration == true && (countryStateId ?? "").isEmpty { return String(localized: "Select a state or region for this country.") }
        return nil
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
