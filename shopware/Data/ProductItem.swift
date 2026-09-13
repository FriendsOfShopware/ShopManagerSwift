import ShopwareDomain
import Foundation
import ShopwareAdminAPI

/// Resolved API values for display. Editors write only changed fields so an
/// unrelated edit never turns a variant's inherited values into overrides.
struct ProductItem: Equatable, Identifiable, Sendable {
    let raw: JSONValue
    let shopURL: String
    var entity: SwEntity { SwEntity(raw) }
    var id: String { entity.id ?? "" }
    var name: String { entity.translated("name") ?? String(localized: "Unnamed product") }
    var productNumber: String { entity.string("productNumber") ?? "" }
    var parentID: String? { entity.string("parentId") }
    var isVariant: Bool { parentID != nil }
    var active: Bool { entity.boolean("active") ?? false }
    var stock: Int { entity.int("stock") ?? 0 }
    var availableStock: Int? { entity.int("availableStock") }
    var sales: Int { entity.int("sales") ?? 0 }
    var childCount: Int { entity.int("childCount") ?? 0 }
    var createdOrder: Double { entity.date("createdAt")?.timeIntervalSince1970 ?? 0 }
    var manufacturer: String { entity.entity("manufacturer")?.translated("name") ?? "" }
    var taxRate: Double? { entity.entity("tax")?.double("taxRate") }
    var taxID: String? { entity.string("taxId") ?? entity.entity("tax")?.id }
    var prices: [JSONValue] { raw["price"]?.arrayValue ?? [] }
    var defaultPrice: JSONValue? { prices.first { $0["currencyId"]?.stringValue == ShopwareDefaults.currencyID } }
    var grossPrice: Double? { defaultPrice?["gross"]?.doubleValue }
    var netPrice: Double? { defaultPrice?["net"]?.doubleValue }
    var priceOrder: Double { grossPrice ?? -.infinity }
    var advancedPrices: [JSONValue] { raw["prices"]?.arrayValue ?? [] }
    var description: String { entity.translated("description") ?? "" }
    var options: [ProductReference] { references("options") }
    var optionLabel: String { options.map(\.name).joined(separator: " · ") }
    var customFields: [String: JSONValue] { raw["customFields"]?.objectValue ?? raw["translated"]?["customFields"]?.objectValue ?? [:] }
    var media: [ProductMediaItem] {
        entity.entities("media").map { ProductMediaItem($0, shopURL: shopURL) }
            .sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
    }
    var coverID: String? { entity.string("coverId") ?? entity.entity("cover")?.id }
    var coverURL: String? {
        entity.entity("cover")?.entity("media")?.string("url").map { rebaseMediaUrl($0, shopURL) }
    }
    var visibilities: [ProductVisibility] { entity.entities("visibilities").map { ProductVisibility($0) } }
    init(_ entity: SwEntity, shopURL: String) { raw = entity.json; self.shopURL = shopURL }
    func references(_ key: String) -> [ProductReference] { entity.entities(key).map { ProductReference($0) } }
}
