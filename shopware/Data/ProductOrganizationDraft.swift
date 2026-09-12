import CryptoKit
import Foundation
import ShopwareAdminAPI

struct ProductOrganizationDraft: Equatable {
    var categories: Set<String>
    var properties: Set<String>
    var tags: Set<String>
    /// Sales channel ID -> Shopware visibility (10 / 20 / 30).
    var visibilities: [String: Int]
    subscript(visibility channel: String) -> Int {
        get { visibilities[channel, default: 30] }
        set { visibilities[channel] = newValue }
    }
    init(_ product: ProductItem) {
        categories = Set(product.references("categories").map(\.id))
        properties = Set(product.references("properties").map(\.id))
        tags = Set(product.references("tags").map(\.id))
        visibilities = Dictionary(product.visibilities.map { ($0.salesChannelID, $0.visibility) }, uniquingKeysWith: { first, _ in first })
    }
    func operations(for original: ProductItem) -> [String: JSONValue] {
        let old = ProductOrganizationDraft(original)
        var patch: [String: JSONValue] = ["id": .string(original.id)]
        var operations: [String: JSONValue] = [:]
        func remove(_ entity: String, _ payload: [JSONValue]) {
            if !payload.isEmpty { operations["remove-" + entity] = .object(["entity": .string(entity), "action": "delete", "payload": .array(payload)]) }
        }
        for (key, entity, field, before, after) in [
            ("categories", "product_category", "categoryId", old.categories, categories),
            ("properties", "product_property", "optionId", old.properties, properties),
            ("tags", "product_tag", "tagId", old.tags, tags),
        ] where before != after {
            remove(entity, before.subtracting(after).sorted().map { id in
                var row: [String: JSONValue] = ["productId": .string(original.id), "productVersionId": .string(ShopwareDefaults.liveVersionID), field: .string(id)]
                if key == "categories" { row["categoryVersionId"] = .string(ShopwareDefaults.liveVersionID) }
                return .object(row)
            })
            patch[key] = .array(after.sorted().map { .object(["id": .string($0)]) })
        }
        if old.visibilities != visibilities {
            remove("product_visibility", original.visibilities.filter { visibilities[$0.salesChannelID] == nil }.map { .object(["id": .string($0.id)]) })
            patch["visibilities"] = .array(visibilities.keys.sorted().map { channel in
                let id = original.visibilities.first { $0.salesChannelID == channel }?.id
                    ?? Self.mappingID(productID: original.id, relation: "visibility", targetID: channel)
                return .object(["id": .string(id), "salesChannelId": .string(channel), "visibility": .int(visibilities[channel]!)])
            })
        }
        operations["save-product"] = .object(["entity": "product", "action": "upsert", "payload": .array([.object(patch)])])
        return operations
    }
    static func mappingID(productID: String, relation: String, targetID: String) -> String {
        SHA256.hash(data: Data("\(productID)/\(relation)/\(targetID)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
