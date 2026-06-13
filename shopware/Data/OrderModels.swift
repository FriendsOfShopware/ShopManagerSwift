import Foundation
import ShopwareAdminAPI

// Live order detail — fetched on demand, not persisted.

struct OrderLineItem: Equatable, Identifiable, Sendable {
    let id = UUID()
    var label: String
    var quantity: Int
    var totalPrice: Double
    var unitPrice: Double = 0
    var productNumber: String?
}

struct TaxLine: Equatable, Identifiable, Sendable {
    let id = UUID()
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

    var id: String { "\(entity):\(entityId)" }
}

struct OrderDocument: Equatable, Identifiable, Sendable {
    var id: String
    var deepLinkCode: String
    var typeName: String
    var typeTechnical: String
    var number: String
}

/// One state_machine_history row — a transition on the order, its payment, or its delivery.
struct OrderTimelineEntry: Equatable, Identifiable, Sendable {
    let id = UUID()
    /// order | order_transaction | order_delivery
    var entity: String
    /// translated target state ("Paid", "In Progress", …)
    var toStateName: String
    var toStateTechnical: String
    /// admin who triggered it; null = system/automatic
    var userLabel: String?
    var createdAtMs: Int64
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
}
