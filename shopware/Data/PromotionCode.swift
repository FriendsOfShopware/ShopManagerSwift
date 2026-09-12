import Foundation
import ShopwareAdminAPI

struct PromotionCode: Equatable, Identifiable, Sendable {
    let id: String
    let code: String
    let redeemed: Bool
    let customerName: String?
    let customerID: String?
    let createdAt: Date?
    init(_ entity: SwEntity) {
        id = entity.id ?? ""; code = entity.string("code") ?? ""
        redeemed = entity.json["payload"] != nil && entity.json["payload"] != .null
        customerName = entity.json["payload"]?["customerName"]?.stringValue
        customerID = entity.json["payload"]?["customerId"]?.stringValue
        createdAt = entity.date("createdAt")
    }
}
