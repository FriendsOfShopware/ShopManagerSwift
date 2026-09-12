import SwiftUI

struct DestinationStack: View {
    let destination: Destination
    let shop: ConnectedShop
    @Bindable var navigation: AppNavigation
    let onAddShop: () -> Void
    let showsShopSwitcher: Bool

    var body: some View {
        NavigationStack(path: $navigation[destination]) {
            DestinationContent(destination: destination, shop: shop, onAddShop: onAddShop)
                .toolbar {
                    #if os(iOS)
                    if showsShopSwitcher {
                        ToolbarItem(placement: .topBarLeading) {
                            ShopSwitcher(shop: shop, onAddShop: onAddShop)
                        }
                    }
                    #endif
                }
        }
    }
}
