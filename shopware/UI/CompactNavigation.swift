import SwiftUI

#if os(iOS)
struct CompactNavigation: View {
    let shop: ConnectedShop
    @Bindable var navigation: AppNavigation
    let onAddShop: () -> Void

    var body: some View {
        TabView(selection: $navigation.selection) {
            ForEach(Destination.compactTabs.filter { $0.isVisible(in: shop) }) { destination in
                Tab(destination.title, systemImage: destination.symbol, value: destination) {
                    DestinationStack(destination: destination, shop: shop, navigation: navigation,
                                     onAddShop: onAddShop, showsShopSwitcher: true)
                }
                .accessibilityIdentifier("navigation.tab.\(destination.id)")
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tabBarMinimizeBehavior(.never)
    }
}
#endif
