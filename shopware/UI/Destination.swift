import SwiftUI

/// One catalog supplies labels, symbols and access rules to every navigation shell.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case home, orders, customers, reports, catalog
    case products, promotions, media, reviews

    var id: String { rawValue }
    static let compactTabs: [Self] = [.home, .orders, .customers, .catalog, .reports]

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .orders: "Orders"
        case .customers: "Customers"
        case .reports: "Reports"
        case .catalog: "Catalog"
        case .products: "Products"
        case .promotions: "Promotions"
        case .media: "Media"
        case .reviews: "Reviews"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .orders: "doc.text"
        case .customers: "person.2"
        case .reports: "chart.bar"
        case .catalog: "square.grid.2x2"
        case .products: "shippingbox"
        case .promotions: "tag"
        case .media: "photo.on.rectangle"
        case .reviews: "star.bubble"
        }
    }

    var requiredScope: String? {
        switch self {
        case .orders, .reports: "order"
        case .customers: "customer"
        case .products: "product"
        case .promotions: "promotion"
        case .media: "media"
        case .reviews: "product_review"
        case .home, .catalog: nil
        }
    }

    func isVisible(in shop: ConnectedShop) -> Bool {
        if self == .catalog { return SidebarGroup.catalog.destinations.contains { $0.isVisible(in: shop) } }
        return requiredScope.map { shop.canRead($0) } ?? true
    }
}
