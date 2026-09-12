import Foundation
import ShopwareAdminAPI

func orderDetailCriteria(_ orderId: String) -> Criteria {
    let criteria = Criteria().setLimit(1).addFilter(Criteria.equals("id", .string(orderId)))
        .addAssociation("lineItems")
        .addAssociation("stateMachineState")
        .addAssociation("orderCustomer.customer")
        .addAssociation("deliveries.stateMachineState")
        .addAssociation("deliveries.shippingMethod")
        .addAssociation("deliveries.shippingOrderAddress.country")
        .addAssociation("deliveries.shippingOrderAddress.countryState")
        .addAssociation("transactions.stateMachineState")
        .addAssociation("transactions.paymentMethod")
        .addAssociation("documents.documentType")
        .addAssociation("billingAddress.country")
        .addAssociation("billingAddress.countryState")
        .addAssociation("currency").addAssociation("salesChannel").addAssociation("language").addAssociation("tags")
    for association in ["transactions", "deliveries", "documents"] {
        criteria.getAssociation(association).addSorting("createdAt", "DESC").addSorting("id")
    }
    criteria.getAssociation("lineItems").addSorting("position").addSorting("id")
    return criteria
}

extension ShopApi {
    func fetchOrderDetail(_ orderId: String, versionId: String = OrderApi.liveVersionId, loadTransitions: Bool = true) async throws -> OrderDetail {
        guard let entity = try await orders.search(orderDetailCriteria(orderId), versionId: versionId).data.first else {
            throw ApiError.notFound(message: String(localized: "Order not found"))
        }
        var detail = parseOrderDetail(entity)
        if loadTransitions {
            for index in detail.states.indices {
                do {
                    detail.states[index].transitions = try await stateMachine.transitions(entity: detail.states[index].entity, id: detail.states[index].entityId)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    detail.states[index].transitionsError = (error as? ApiError)?.message ?? error.localizedDescription
                }
            }
            for index in detail.payments.indices {
                if let state = detail.states.first(where: { $0.id == detail.payments[index].state.id }) { detail.payments[index].state = state }
            }
            for index in detail.deliveries.indices {
                if let state = detail.states.first(where: { $0.id == detail.deliveries[index].state.id }) { detail.deliveries[index].state = state }
            }
        }
        return detail
    }
}

func parseOrderState(_ record: SwEntity, entity: String, method: String? = nil) -> OrderStateInfo {
    let state = record.entity("stateMachineState")
    let label: String
    switch entity {
    case "order_transaction": label = String(localized: "Payment")
    case "order_delivery": label = String(localized: "Delivery")
    default: label = String(localized: "Order")
    }
    return OrderStateInfo(entity: entity, entityId: record.id ?? "", label: label,
                          stateName: state?.translated("name") ?? "—", stateTechnical: state?.string("technicalName") ?? "",
                          transitions: [], method: method)
}

/// Prefer Shopware's primary record; older shops fall back to the latest non-failed payment.
func primaryOrderTransaction(_ order: SwEntity) -> SwEntity? {
    let transactions = order.entities("transactions").sorted {
        let lhs = $0.date("createdAt") ?? .distantPast
        let rhs = $1.date("createdAt") ?? .distantPast
        return lhs == rhs ? ($0.id ?? "") > ($1.id ?? "") : lhs > rhs
    }
    if let primary = order.string("primaryOrderTransactionId"), let transaction = transactions.first(where: { $0.id == primary }) { return transaction }
    return transactions.first { !["failed", "cancelled"].contains($0.entity("stateMachineState")?.string("technicalName") ?? "") } ?? transactions.first
}

func primaryOrderDelivery(_ order: SwEntity) -> SwEntity? {
    let deliveries = order.entities("deliveries").sorted {
        let lhs = $0.date("createdAt") ?? .distantPast
        let rhs = $1.date("createdAt") ?? .distantPast
        return lhs == rhs ? ($0.id ?? "") < ($1.id ?? "") : lhs < rhs
    }
    if let primary = order.string("primaryOrderDeliveryId"), let delivery = deliveries.first(where: { $0.id == primary }) { return delivery }
    return deliveries.first { ($0.entity("shippingCosts")?.double("totalPrice") ?? 0) >= 0 } ?? deliveries.first
}

func parseOrderDetail(_ order: SwEntity) -> OrderDetail {
    let customer = order.entity("orderCustomer")
    let billing = order.entity("billingAddress").map(parseEditableAddress)
    let primaryPayment = primaryOrderTransaction(order)
    let primaryDelivery = primaryOrderDelivery(order)
    let deliveries = order.entities("deliveries").compactMap { delivery -> OrderDelivery? in
        guard let id = delivery.id else { return nil }
        let method = delivery.entity("shippingMethod")?.translated("name") ?? "—"
        return OrderDelivery(id: id, method: method, address: delivery.entity("shippingOrderAddress").map(parseEditableAddress),
                             trackingCodes: delivery.json["trackingCodes"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                             trackingURL: delivery.entity("shippingMethod")?.string("trackingUrl"),
                             shippingDateEarliest: delivery.date("shippingDateEarliest"), shippingDateLatest: delivery.date("shippingDateLatest"),
                             shippingCosts: delivery.json["shippingCosts"] ?? .object([:]),
                             state: parseOrderState(delivery, entity: "order_delivery", method: method), primary: id == primaryDelivery?.id)
    }
    let payments = order.entities("transactions").compactMap { payment -> OrderPayment? in
        guard let id = payment.id else { return nil }
        let method = payment.entity("paymentMethod")?.translated("name") ?? "—"
        return OrderPayment(id: id, method: method, amount: payment.entity("amount")?.double("totalPrice") ?? 0,
                            createdAt: payment.date("createdAt"), state: parseOrderState(payment, entity: "order_transaction", method: method),
                            primary: id == primaryPayment?.id)
    }
    let price = order.entity("price")
    var taxes: [Double: Double] = [:]
    for tax in price?.entities("calculatedTaxes") ?? [] {
        if let rate = tax.double("taxRate"), let amount = tax.double("tax") { taxes[rate, default: 0] += amount }
    }
    let items = order.entities("lineItems").compactMap { item -> OrderLineItem? in
        guard let id = item.id else { return nil }
        return OrderLineItem(id: id, label: item.string("label") ?? "—", quantity: item.int("quantity") ?? 1,
                             totalPrice: item.double("totalPrice") ?? 0, unitPrice: item.double("unitPrice") ?? 0,
                             productNumber: item.entity("payload")?.string("productNumber"), productId: item.string("productId"),
                             type: item.string("type") ?? "custom", parentId: item.string("parentId"), position: item.int("position") ?? 0,
                             description: item.string("description"), priceDefinition: item.json["priceDefinition"] ?? .object([:]),
                             payload: item.json["payload"] ?? .object([:]))
    }.sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
    let documents = order.entities("documents").compactMap { document -> OrderDocument? in
        guard let id = document.id else { return nil }
        let config = document.entity("config")
        return OrderDocument(id: id, deepLinkCode: document.string("deepLinkCode") ?? "",
                             typeName: document.entity("documentType")?.translated("name") ?? String(localized: "Document"),
                             typeTechnical: document.entity("documentType")?.string("technicalName") ?? "",
                             number: document.string("documentNumber") ?? config?.string("documentNumber") ?? "",
                             createdAt: document.date("createdAt"), documentDate: config?.string("documentDate"),
                             referencedDocumentId: document.string("referencedDocumentId"), staticDocument: document.boolean("static") ?? false,
                             hasFile: document.boolean("static") != true || document.string("documentMediaFileId") != nil,
                             sent: document.boolean("sent") ?? false, config: document.json["config"] ?? .object([:]))
    }
    let name = [customer?.string("firstName"), customer?.string("lastName")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    let shipping = deliveries.first(where: \.primary)
    return OrderDetail(id: order.id ?? "", orderNumber: order.string("orderNumber") ?? "—",
                       orderDateTime: order.string("orderDateTime") ?? "", customerName: name.isEmpty ? String(localized: "Guest") : name,
                       customerEmail: customer?.string("email") ?? "", currencyIso: order.entity("currency")?.string("isoCode"),
                       amountTotal: order.double("amountTotal") ?? price?.double("totalPrice") ?? 0,
                       shippingTotal: order.double("shippingTotal") ?? 0, netTotal: order.double("amountNet") ?? price?.double("netPrice") ?? 0,
                       taxes: taxes.keys.sorted().map { TaxLine(rate: $0, amount: taxes[$0] ?? 0) },
                       paymentMethod: payments.first(where: \.primary)?.method, shippingMethod: shipping?.method, deliveryId: shipping?.id,
                       trackingCodes: shipping?.trackingCodes ?? [], billingAddress: billing?.formatted, shippingAddress: shipping?.address?.formatted,
                       phone: billing?.phoneNumber ?? shipping?.address?.phoneNumber,
                       customerComment: order.string("customerComment"), internalComment: order.string("internalComment"), lineItems: items,
                       states: [parseOrderState(order, entity: "order")] + payments.map(\.state) + deliveries.map(\.state), documents: documents,
                       placedAt: order.date("orderDateTime"), customerId: customer?.string("customerId"), orderCustomerId: customer?.id,
                       customerNumber: customer?.string("customerNumber") ?? customer?.entity("customer")?.string("customerNumber") ?? "",
                       company: customer?.string("company") ?? "", salesChannelId: order.string("salesChannelId") ?? "",
                       salesChannel: order.entity("salesChannel")?.translated("name") ?? "—", language: order.entity("language")?.string("name") ?? "—",
                       affiliateCode: order.string("affiliateCode") ?? "", campaignCode: order.string("campaignCode") ?? "",
                       deepLinkCode: order.string("deepLinkCode") ?? "", taxStatus: price?.string("taxStatus") ?? "gross",
                       positionPrice: order.double("positionPrice") ?? price?.double("positionPrice") ?? 0,
                       unroundedTotal: price?.double("rawTotal") ?? order.double("amountTotal") ?? 0,
                       currencyDecimals: order.entity("totalRounding")?.int("decimals") ?? 2, billing: billing, deliveries: deliveries, payments: payments,
                       tags: order.entities("tags").compactMap { tag in tag.id.map { CustomerOption(id: $0, name: tag.string("name") ?? "") } },
                       customFields: order.json["customFields"]?.objectValue ?? [:], source: order.json)
}
