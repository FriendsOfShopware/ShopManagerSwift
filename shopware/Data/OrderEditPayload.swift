import Foundation
import ShopwareAdminAPI

/// Writes only changed order fields into the isolated version. Relationship removals are explicit.
func orderEditPayload(draft: OrderDetail, original: OrderDetail) -> JSONValue {
    var fields: [String: JSONValue] = [:]
    if draft.customerEmail != original.customerEmail, let id = draft.orderCustomerId {
        fields["orderCustomer"] = .object(["id": .string(id), "email": .string(draft.customerEmail.trimmed)])
    }
    for (key, value, previous) in [
        ("affiliateCode", draft.affiliateCode, original.affiliateCode),
        ("campaignCode", draft.campaignCode, original.campaignCode),
        ("customerComment", draft.customerComment ?? "", original.customerComment ?? ""),
        ("internalComment", draft.internalComment ?? "", original.internalComment ?? ""),
    ] where value != previous { fields[key] = value.trimmed.isEmpty ? .null : .string(value.trimmed) }
    if draft.customFields != original.customFields {
        var changed = draft.customFields.filter { original.customFields[$0.key] != $0.value }
        for key in original.customFields.keys where draft.customFields[key] == nil { changed[key] = .null }
        fields["customFields"] = .object(changed)
    }
    if draft.tags != original.tags { fields["tags"] = .array(draft.tags.map { .object(["id": .string($0.id)]) }) }
    var addresses: [String: EditableAddress] = [:]
    if let billing = draft.billing, billing != original.billing { addresses[billing.id] = billing }
    for delivery in draft.deliveries {
        if let address = delivery.address, address != original.deliveries.first(where: { $0.id == delivery.id })?.address { addresses[address.id] = address }
    }
    if !addresses.isEmpty { fields["addresses"] = .array(addresses.keys.sorted().compactMap { addresses[$0]?.payload }) }
    let deliveries = draft.deliveries.compactMap { delivery -> JSONValue? in
        guard let previous = original.deliveries.first(where: { $0.id == delivery.id }), delivery.shippingCosts != previous.shippingCosts else { return nil }
        return .object(["id": .string(delivery.id), "shippingCosts": delivery.shippingCosts])
    }
    if !deliveries.isEmpty { fields["deliveries"] = .array(deliveries) }
    let items = draft.lineItems.compactMap { item -> JSONValue? in
        guard let previous = original.lineItems.first(where: { $0.id == item.id }), item != previous else { return nil }
        var values: [String: JSONValue] = ["id": .string(item.id)]
        if item.label != previous.label { values["label"] = .string(item.label) }
        if item.quantity != previous.quantity { values["quantity"] = .int(item.quantity) }
        var definition = item.priceDefinition.objectValue ?? [:]
        if item.unitPrice != previous.unitPrice { definition["price"] = .number(item.unitPrice) }
        if item.quantity != previous.quantity && definition["quantity"] != nil { definition["quantity"] = .int(item.quantity) }
        if definition != (previous.priceDefinition.objectValue ?? [:]) { values["priceDefinition"] = .object(definition) }
        return values.count > 1 ? .object(values) : nil
    }
    if !items.isEmpty { fields["lineItems"] = .array(items) }
    return .object(fields)
}

struct OrderCartIssue: Identifiable, Equatable {
    let id: String
    let message: String
    let blocksOrder: Bool
}

func orderCartIssues(_ response: JSONValue) -> [OrderCartIssue] {
    let errors = response["errors"]
    let keyed: [(String, JSONValue)]
    if let values = errors?.objectValue { keyed = values.keys.sorted().compactMap { key in values[key].map { (key, $0) } } }
    else { keyed = (errors?.arrayValue ?? []).map { value in (value["key"]?.stringValue ?? value["id"]?.stringValue ?? String(decoding: value.encoded(sortedKeys: true), as: UTF8.self), value) } }
    var seen = Set<String>()
    return keyed.compactMap { key, error in
        guard seen.insert(key).inserted else { return nil }
        return OrderCartIssue(id: key, message: error["message"]?.stringValue ?? error["detail"]?.stringValue ?? error["messageKey"]?.stringValue ?? String(localized: "Order validation failed."),
                              blocksOrder: error["blockOrder"]?.boolValue ?? true)
    }
}
