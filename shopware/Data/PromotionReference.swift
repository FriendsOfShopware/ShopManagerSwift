import ShopwareAdminAPI

struct PromotionReference: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    var mappingID: String?
    init(id: String, name: String, mappingID: String? = nil) {
        self.id = id; self.name = name; self.mappingID = mappingID
    }
    init(_ entity: SwEntity) { id = entity.id ?? ""; name = customerEntityLabel(entity) }
}
