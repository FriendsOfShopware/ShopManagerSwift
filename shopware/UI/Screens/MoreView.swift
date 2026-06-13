import SwiftUI

/// ACL-gated menu routing to Products, Promotions, Media and Reviews. Each entry shows only when
/// the connected login can read that entity.
struct MoreView: View {
    let shop: ConnectedShop

    private struct Entry: Identifiable {
        let dest: MoreDest
        let symbol: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let scope: String
        var id: String { dest.rawValue }
    }

    private var entries: [Entry] {
        [
            Entry(dest: .products, symbol: "shippingbox", title: "Products",
                  subtitle: "Stock, price, and quick edits", scope: "product"),
            Entry(dest: .promos, symbol: "tag", title: "Promotions",
                  subtitle: "Toggle and generate codes", scope: "promotion"),
            Entry(dest: .media, symbol: "photo.on.rectangle", title: "Media",
                  subtitle: "Browse and upload files", scope: "media"),
            Entry(dest: .reviews, symbol: "star.bubble", title: "Reviews",
                  subtitle: "Approve or reject", scope: "product_review"),
        ].filter { shop.canRead($0.scope) }
    }

    var body: some View {
        List(entries) { entry in
            NavigationLink(value: entry.dest) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: entry.symbol).foregroundStyle(Theme.accent)
                }
            }
        }
        .navigationTitle("More")
        .navigationDestination(for: MoreDest.self) { dest in
            switch dest {
            case .products: ProductsView(shop: shop)
            case .promos: PromosView(shop: shop)
            case .media: MediaView(shop: shop)
            case .reviews: ReviewInboxView(shop: shop)
            }
        }
    }
}
