import Foundation
import CryptoKit
import ShopwareAdminAPI

struct PromotionConditionsDraft: Equatable {
    var preventCombination: Bool
    var exclusions: Set<String>
    var salesChannels: Set<String>
    var personaRules: Set<String>
    var cartRules: Set<String>
    var orderRules: Set<String>
    init(_ item: PromotionItem) {
        preventCombination = item.preventCombination; exclusions = item.exclusionIDs
        salesChannels = Set(item.salesChannels.map(\.id)); personaRules = Set(item.personaRules.map(\.id))
        cartRules = Set(item.cartRules.map(\.id)); orderRules = Set(item.orderRules.map(\.id))
    }
    func operations(for original: PromotionItem) -> [String: JSONValue] {
        func references(_ ids: Set<String>) -> JSONValue { .array(ids.sorted().map { .object(["id": .string($0)]) }) }
        let channels = salesChannels.sorted().map { id -> JSONValue in
            // Stable IDs make retrying a request safe even if its response was lost.
            let existingMappingID = original.salesChannels.first { $0.id == id }?.mappingID
            let mappingID = existingMappingID
                ?? SHA256.hash(data: Data("\(original.id)/sales-channel/\(id)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
            return PromotionApi.salesChannelMapping(id: mappingID, salesChannelID: id, isNew: existingMappingID == nil)
        }
        let patch: JSONValue = .object([
            "id": .string(original.id), "preventCombination": .bool(preventCombination),
            "exclusionIds": .array(exclusions.subtracting([original.id]).sorted().map(JSONValue.string)),
            "salesChannels": .array(channels), "personaRules": references(personaRules),
            "cartRules": references(cartRules), "orderRules": references(orderRules),
        ])
        var operations: [String: JSONValue] = [:]
        func remove(_ key: String, _ entity: String, _ rows: [JSONValue]) {
            if !rows.isEmpty { operations[key] = .object(["entity": .string(entity), "action": "delete", "payload": .array(rows)]) }
        }
        remove("remove-sales-channels", "promotion_sales_channel", original.salesChannels.filter { !salesChannels.contains($0.id) }.compactMap { $0.mappingID.map { .object(["id": .string($0)]) } })
        for (key, old, new) in [("persona", original.personaRules, personaRules), ("cart", original.cartRules, cartRules), ("order", original.orderRules, orderRules)] {
            remove("remove-\(key)-rules", "promotion_\(key)_rule", old.filter { !new.contains($0.id) }.map {
                .object(["promotionId": .string(original.id), "ruleId": .string($0.id)])
            })
        }
        operations["save-promotion"] = .object(["entity": "promotion", "action": "upsert", "payload": .array([patch])])
        return operations
    }
}
