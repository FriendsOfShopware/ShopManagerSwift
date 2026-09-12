import ShopwareAdminAPI

struct ProductReference: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let group: String?
    init(_ entity: SwEntity) {
        id = entity.id ?? ""
        name = customerEntityLabel(entity)
        group = entity.entity("group")?.translated("name")
    }
}
