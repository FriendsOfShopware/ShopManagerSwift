import ShopwareAdminAPI

struct ProductCurrency: Equatable, Identifiable, Sendable {
    let id: String
    let code: String
    let factor: Double
    init(_ entity: SwEntity) {
        id = entity.id ?? ""; code = entity.string("isoCode") ?? ""
        factor = entity.double("factor") ?? 1
    }
}
