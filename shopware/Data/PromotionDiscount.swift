import Foundation
import ShopwareAdminAPI

struct PromotionDiscount: Equatable, Identifiable, Sendable {
    let id: String
    let scope: String
    let type: String
    let value: Double
    let maxValue: Double?
    let advanced: Bool
    let rules: [PromotionReference]
    let prices: [JSONValue]
    let sorter: String
    let applier: String
    let usage: String
    let picker: String
    init(_ entity: SwEntity) {
        id = entity.id ?? ""; scope = entity.string("scope") ?? "cart"; type = entity.string("type") ?? "percentage"
        value = entity.double("value") ?? 0; maxValue = entity.double("maxValue")
        advanced = entity.boolean("considerAdvancedRules") ?? false
        rules = entity.entities("discountRules").map { PromotionReference($0) }
        prices = entity.entities("promotionDiscountPrices").map(\.json)
        sorter = entity.string("sorterKey") ?? ""; applier = entity.string("applierKey") ?? ""
        usage = entity.string("usageKey") ?? ""; picker = entity.string("pickerKey") ?? ""
    }
    var scopeTitle: String {
        switch scope {
        case "cart": String(localized: "Cart")
        case "delivery": String(localized: "Shipping")
        case "set": String(localized: "Product set")
        default: scope.hasPrefix("setgroup") ? String(localized: "Product group") : scope
        }
    }
    var typeTitle: String {
        switch type {
        case "percentage": String(localized: "Percentage")
        case "absolute": String(localized: "Amount off")
        case "fixed": String(localized: "Fixed price")
        case "fixed_unit": String(localized: "Fixed unit price")
        default: type
        }
    }
}
