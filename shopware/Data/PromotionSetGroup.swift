import Foundation
import ShopwareAdminAPI

struct PromotionSetGroup: Equatable, Identifiable, Sendable {
    let id: String
    let packager: String
    let value: String
    let rules: [PromotionReference]
    var title: String {
        switch packager {
        case "COUNT": String(localized: "Quantity")
        case "PRICE_UNIT_GROSS": String(localized: "Gross unit price")
        case "PRICE_UNIT_NET": String(localized: "Net unit price")
        default: packager
        }
    }
    init(_ entity: SwEntity) {
        id = entity.id ?? ""; packager = entity.string("packagerKey") ?? ""
        value = entity.string("value") ?? entity.double("value").map { String($0) } ?? ""
        rules = entity.entities("setGroupRules").map { PromotionReference($0) }
    }
}
