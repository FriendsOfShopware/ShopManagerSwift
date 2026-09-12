import SwiftUI

struct CatalogView: View {
    let shop: ConnectedShop
    let onAddShop: () -> Void

    var body: some View {
        List {
            ForEach(SidebarGroup.catalog.destinations.filter { $0.isVisible(in: shop) }) { destination in
                NavigationLink(value: destination) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(destination.title)
                            subtitle(for: destination).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } icon: {
                        Image(systemName: destination.symbol).foregroundStyle(.tint)
                    }
                }
                .accessibilityIdentifier("navigation.destination.\(destination.id)")
            }
        }
        .groupedListStyle()
        .navigationTitle("Catalog")
        .navigationDestination(for: Destination.self) { destination in
            DestinationContent(destination: destination, shop: shop, onAddShop: onAddShop)
        }
    }

    private func subtitle(for destination: Destination) -> Text {
        switch destination {
        case .products: Text("Stock, price, and quick edits")
        case .promotions: Text("Toggle and generate codes")
        case .media: Text("Browse and upload files")
        case .reviews: Text("Approve or reject")
        default: Text(verbatim: "")
        }
    }
}
