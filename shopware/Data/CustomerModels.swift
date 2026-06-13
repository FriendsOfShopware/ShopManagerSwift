import Foundation

/// A row in the customers listing — fetched live through the listing pager.
struct CustomerRow: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var orderCount: Int
    var totalSpend: Double
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
}

// Pickers loaded once for the edit sheet.
struct SalutationOption: Equatable, Identifiable, Sendable {
    var id: String
    var label: String
}

struct CountryOption: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
}
