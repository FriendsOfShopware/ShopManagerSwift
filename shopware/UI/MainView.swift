import SwiftUI

struct MainView: View {
    @Environment(AppViewModel.self) private var model
    let onAddShop: () -> Void
    @State private var navigation = AppNavigation()

    var body: some View {
        if let shop = model.selectedShop {
            content(for: shop)
                .id(shop.id)
                .task(id: shop.id) { model.refreshIfStale(shop) }
                .onChange(of: shop.id) {
                    navigation.reset(for: shop)
                    consumeDeepLink()
                }
                .onChange(of: shop.scopes) { navigation.validateSelection(for: shop) }
                .onChange(of: pendingDeepLinkKey) { consumeDeepLink() }
                .onAppear {
                    navigation.validateSelection(for: shop)
                    consumeDeepLink()
                }
        } else {
            NoShopsView(onAddShop: onAddShop)
        }
    }

    private var pendingDeepLinkKey: String? {
        model.pendingDeepLink.map { "\($0.shopId):\($0.orderId ?? "")" }
    }

    private func consumeDeepLink() {
        guard let link = model.pendingDeepLink, let shop = model.selectedShop,
              navigation.openOrder(link.orderId, shopID: link.shopId, in: shop) else { return }
        model.pendingDeepLink = nil
    }

    @ViewBuilder
    private func content(for shop: ConnectedShop) -> some View {
        #if os(macOS)
        SidebarNavigation(shop: shop, navigation: navigation, onAddShop: onAddShop)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Keep the detail alive when a narrow window collapses the sidebar.
            SidebarNavigation(shop: shop, navigation: navigation, onAddShop: onAddShop)
        } else {
            CompactNavigation(shop: shop, navigation: navigation, onAddShop: onAddShop)
        }
        #endif
    }
}

struct NoShopsView: View {
    let onAddShop: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No shops connected", systemImage: "storefront")
        } description: {
            Text("Connect a Shopware shop to get started.")
        } actions: {
            Button("Connect a shop", action: onAddShop)
                .buttonStyle(.glassProminent)
        }
    }
}
