import Foundation
import ShopwareAdminAPI

/// A row in the customers listing — fetched live through the listing pager.
struct CustomerRow: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var orderCount: Int
    var totalSpend: Double
    var email: String = ""
    var customerNumber: String = ""
    var active: Bool = false
    var guest: Bool = false
    var company: String = ""
    var group: String = ""
    var street: String = ""
    var zipcode: String = ""
    var city: String = ""
    var createdAt: Date = .distantPast
    var boundSalesChannel: String = ""
    var affiliateCode: String = ""
    var campaignCode: String = ""
    var requestedGroup: String?
}

// Live customer detail — fetched on demand, not persisted.
struct CustomerDetail: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var email: String
    var customerNumber: String
    var group: String?
    var active: Bool
    var guest: Bool
    var orderCount: Int
    var totalSpend: Double
    var lastOrderMs: Int64?
    var customerSince: String?
    var billingAddress: String?
    var shippingAddress: String?
    var phone: String?
    // Structured fields for the edit sheet (display uses the formatted strings above).
    var firstName: String = ""
    var lastName: String = ""
    var title: String?
    var company: String?
    var salutationId: String?
    var billing: EditableAddress?
    var shipping: EditableAddress?
    /// true when billing and shipping point at the same address record
    var sharedAddress: Bool = false
    var accountType: String = "private"
    var vatIds: [String] = []
    var groupId: String = ""
    var languageId: String = ""
    var language: String = ""
    var salesChannelId: String = ""
    var salesChannel: String = ""
    var boundSalesChannelId: String?
    var boundSalesChannel: String?
    var lastLogin: Date?
    var birthday: String?
    var affiliateCode: String?
    var campaignCode: String?
    var doubleOptInRegistration: Bool = false
    var doubleOptInConfirmDate: Date?
    var requestedGroupId: String?
    var requestedGroup: String?
    var tags: [CustomerOption] = []
    var customFields: [String: JSONValue] = [:]
    var createdByAdmin: Bool = false
    var defaultBillingAddressId: String?
    var defaultShippingAddressId: String?
}

/// One editable address record (customer_address). countryName is for display only.
struct EditableAddress: Equatable, Identifiable, Sendable {
    var id: String
    var firstName: String = ""
    var lastName: String = ""
    var street: String = ""
    var additionalLine: String?
    var zipcode: String = ""
    var city: String = ""
    var company: String?
    var phoneNumber: String?
    var countryId: String?
    var countryName: String?
    var salutationId: String?
    var title: String?
    var department: String?
    var additionalLine2: String?
    var countryStateId: String?
    var countryStateName: String?
    var customFields: [String: JSONValue] = [:]

    var formatted: String {
        [company, department, [title, firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
         street, additionalLine, additionalLine2, [zipcode, city].filter { !$0.isEmpty }.joined(separator: " "),
         countryStateName, countryName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

// Pickers loaded once for the edit sheet.
struct SalutationOption: Equatable, Identifiable, Sendable {
    var id: String
    var label: String
}

struct CountryOption: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var postalCodeRequired: Bool = false
    var forceStateInRegistration: Bool = false
}
