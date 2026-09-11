import Foundation
import ShopwareAdminAPI

struct CustomerCreateDraft {
    var customer: CustomerDetail
    var address: EditableAddress
    var password = ""
    var passwordConfirmation = ""

    init() {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        customer = parseCustomerDetail(SwEntity(.object(["id": .string(id), "active": true])))
        address = EditableAddress(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
    }

    func validationError(country: CountryOption?) -> String? {
        var general = CustomerDraft(customer)
        general.password = password
        general.passwordConfirmation = passwordConfirmation
        if let error = general.validationError { return error }
        if customer.salesChannelId.isEmpty { return String(localized: "Select a sales channel.") }
        if !customer.guest && password.isEmpty { return String(localized: "A password is required for a registered customer.") }
        return address.validationError(country: country, business: customer.accountType == "business")
    }

    func payload(number: String, boundToSalesChannel: Bool) -> JSONValue {
        var fields = CustomerDraft(customer).fields(customer)
        fields["id"] = .string(customer.id)
        fields["customerNumber"] = .string(number)
        fields["salesChannelId"] = .string(customer.salesChannelId)
        fields["boundSalesChannelId"] = boundToSalesChannel ? .string(customer.salesChannelId) : .null
        fields["guest"] = .bool(customer.guest)
        if !customer.guest { fields["password"] = .string(password) }
        fields["addresses"] = .array([address.payload])
        fields["defaultBillingAddressId"] = .string(address.id)
        fields["defaultShippingAddressId"] = .string(address.id)
        return .object(fields)
    }
}
