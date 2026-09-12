import SwiftUI

/// Native sidebar for Mac and iPad, including the system's compact-window navigation.
struct SidebarNavigation: View {
    let shop: ConnectedShop
    @Bindable var navigation: AppNavigation
    let onAddShop: () -> Void
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @ScaledMetric(relativeTo: .body) private var idealColumnWidth = 250
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            List(selection: $navigation.sidebarSelection) {
                ForEach(SidebarGroup.allCases) { group in
                    let destinations = group.destinations.filter { $0.isVisible(in: shop) }
                    if !destinations.isEmpty {
                        Section(group.title) {
                            ForEach(destinations) { destination in
                                NavigationLink(value: destination) {
                                    Label(destination.title, systemImage: destination.symbol)
                                }
                                .accessibilityIdentifier("navigation.destination.\(destination.id)")
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("navigation.sidebar")
            .navigationSplitViewColumnWidth(min: 220, ideal: min(idealColumnWidth, 420), max: 480)
            .safeAreaInset(edge: .top, spacing: 0) {
                ShopSwitcher(shop: shop, onAddShop: onAddShop, inSidebar: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } detail: {
            DestinationStack(destination: navigation.selection, shop: shop, navigation: navigation,
                             onAddShop: onAddShop, showsShopSwitcher: showsShopSwitcher)
                .id(navigation.selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var showsShopSwitcher: Bool {
        #if os(iOS)
        sizeClass == .compact || visibility == .detailOnly
        #else
        false
        #endif
    }
}
