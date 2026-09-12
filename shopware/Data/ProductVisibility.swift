import Foundation
import ShopwareAdminAPI

struct ProductVisibility: Equatable, Identifiable, Sendable {
    let id: String
    let salesChannelID: String
    let name: String
    var visibility: Int
    init(_ entity: SwEntity) {
        id = entity.id ?? ""
        salesChannelID = entity.string("salesChannelId") ?? entity.entity("salesChannel")?.id ?? ""
        name = entity.entity("salesChannel")?.translated("name") ?? salesChannelID
        visibility = entity.int("visibility") ?? 30
    }
    var label: LocalizedStringResource {
        switch visibility {
        case 10: "Direct link only"
        case 20: "Search and direct link"
        default: "Visible everywhere"
        }
    }
}
