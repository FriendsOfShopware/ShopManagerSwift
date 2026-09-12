import SwiftUI

struct DestinationContent: View {
    let destination: Destination
    let shop: ConnectedShop
    let onAddShop: () -> Void

    var body: some View {
        switch destination {
        case .home: HomeView(shop: shop, onAddShop: onAddShop)
        case .orders: OrdersView(shop: shop)
        case .customers: CustomersView(shop: shop)
        case .reports: ReportsView(shop: shop)
        case .catalog: CatalogView(shop: shop, onAddShop: onAddShop)
        case .products: ProductsView(shop: shop)
        case .promotions: PromosView(shop: shop)
        case .media: MediaView(shop: shop)
        case .reviews: ReviewInboxView(shop: shop)
        }
    }
}
