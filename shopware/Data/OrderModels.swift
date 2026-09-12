import Foundation
import ShopwareAdminAPI

// Live order detail — fetched on demand, not persisted.

struct OrderLineItem: Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var quantity: Int
    var totalPrice: Double
    var unitPrice: Double = 0
    var productNumber: String?
    var productId: String?
    var type: String = "product"
    var parentId: String?
    var position: Int = 0
    var description: String?
    var priceDefinition: JSONValue = .object([:])
    var payload: JSONValue = .object([:])
}

struct TaxLine: Equatable, Identifiable, Sendable {
    var id: Double { rate }
    var rate: Double
    var amount: Double
}

struct OrderStateInfo: Equatable, Identifiable, Sendable {
    /// order | order_transaction | order_delivery
    var entity: String
    var entityId: String
    /// Order / Payment / Delivery
    var label: String
    var stateName: String
    var stateTechnical: String
    var transitions: [StateTransition]
    var transitionsError: String?
    var method: String?

    var id: String { "\(entity):\(entityId)" }
}

struct OrderDocument: Equatable, Identifiable, Sendable {
    var id: String
    var deepLinkCode: String
    var typeName: String
    var typeTechnical: String
    var number: String
    var createdAt: Date?
    var documentDate: String?
    var referencedDocumentId: String?
    var staticDocument = false
    var hasFile = true
    var sent = false
    var config: JSONValue = .object([:])
}

/// One state_machine_history row — a transition on the order, its payment, or its delivery.
struct OrderTimelineEntry: Equatable, Identifiable, Sendable {
    var id: String
    /// order | order_transaction | order_delivery
    var entity: String
    /// translated target state ("Paid", "In Progress", …)
    var toStateName: String
    var toStateTechnical: String
    /// admin who triggered it; null = system/automatic
    var userLabel: String?
    var createdAtMs: Int64
    var fromStateName: String?
    var fromStateTechnical: String?
}

struct OrderPayment: Equatable, Identifiable, Sendable {
    var id: String
    var method: String
    var amount: Double
    var createdAt: Date?
    var state: OrderStateInfo
    var primary: Bool
}

struct OrderDelivery: Equatable, Identifiable, Sendable {
    var id: String
    var method: String
    var address: EditableAddress?
    var trackingCodes: [String]
    var trackingURL: String?
    var shippingDateEarliest: Date?
    var shippingDateLatest: Date?
    var shippingCosts: JSONValue
    var state: OrderStateInfo
    var primary: Bool
}

struct OrderDetail: Equatable, Identifiable, Sendable {
    var id: String
    var orderNumber: String
    var orderDateTime: String
    var customerName: String
    var customerEmail: String
    /// order currency; null = shop default
    var currencyIso: String?
    var amountTotal: Double
    var shippingTotal: Double
    var netTotal: Double
    var taxes: [TaxLine]
    var paymentMethod: String?
    var shippingMethod: String?
    var deliveryId: String?
    var trackingCodes: [String]
    var billingAddress: String?
    var shippingAddress: String?
    var phone: String?
    var customerComment: String?
    var internalComment: String?
    var lineItems: [OrderLineItem]
    var states: [OrderStateInfo]
    var documents: [OrderDocument] = []
    var placedAt: Date?
    var customerId: String?
    var orderCustomerId: String?
    var customerNumber: String = ""
    var company: String = ""
    var salesChannelId: String = ""
    var salesChannel: String = ""
    var language: String = ""
    var affiliateCode: String = ""
    var campaignCode: String = ""
    var deepLinkCode: String = ""
    var taxStatus: String = "gross"
    var positionPrice: Double = 0
    var unroundedTotal: Double = 0
    var currencyDecimals: Int = 2
    var billing: EditableAddress?
    var deliveries: [OrderDelivery] = []
    var payments: [OrderPayment] = []
    var tags: [CustomerOption] = []
    var customFields: [String: JSONValue] = [:]
    var source: JSONValue = .object([:])
}
