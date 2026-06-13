import SwiftUI

/// Lists the connected shops; each row opens its per-shop settings.
struct ManageShopsView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        List {
            ForEach(model.data.shops) { shop in
                NavigationLink(value: ShopSettingsRoute(id: shop.id)) {
                    HStack(spacing: 12) {
                        ShopIconBox(tint: shop.tint, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shop.name).font(.subheadline.weight(.medium))
                            Text(shop.baseUrl.replacingOccurrences(of: "https://", with: ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Shops")
        .navigationDestination(for: ShopSettingsRoute.self) { route in
            if let shop = model.shop(route.id) {
                ShopSettingsView(shop: shop)
            }
        }
    }
}

struct ShopSettingsRoute: Hashable { let id: String }
