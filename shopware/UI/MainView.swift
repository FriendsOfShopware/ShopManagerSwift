import SwiftUI

/// The app's five primary destinations. `requiredScope` gates a tab on the connected login's read
/// access (wizard ACL probes); nil = always visible.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, orders, customers, reports, more

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .orders: "Orders"
        case .customers: "Customers"
        case .reports: "Reports"
        case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .orders: "doc.text"
        case .customers: "person.2"
        case .reports: "chart.bar"
        case .more: "square.grid.2x2"
        }
    }

    var requiredScope: String? {
        switch self {
        case .orders, .reports: "order"
        case .customers: "customer"
        default: nil
        }
    }
}

/// Sub-destinations of the More tab.
enum MoreDest: String, Hashable, Identifiable {
    case products, promos, media, reviews
    var id: String { rawValue }
}

struct MainView: View {
    @Environment(AppViewModel.self) private var model
    let onAddShop: () -> Void

    @State private var selection: AppTab = .home

    var body: some View {
        if let shop = model.selectedShop {
            content(for: shop)
                .task(id: shop.id) { model.refreshIfStale(shop) }
        } else {
            NoShopsView(onAddShop: onAddShop)
        }
    }

    private var visibleTabs: [AppTab] {
        guard let shop = model.selectedShop else { return AppTab.allCases }
        return AppTab.allCases.filter { tab in
            guard let scope = tab.requiredScope else { return true }
            return shop.canRead(scope)
        }
    }

    @ViewBuilder
    private func content(for shop: ConnectedShop) -> some View {
        TabView(selection: $selection) {
            ForEach(visibleTabs) { tab in
                Tab(tab.titleKey, systemImage: tab.symbol, value: tab) {
                    tabRoot(tab, shop: shop)
                }
            }
        }
        #if os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        // Collapse the (Liquid Glass) tab bar as content scrolls up.
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .onChange(of: shop.id) {
            if !visibleTabs.contains(selection) { selection = .home }
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab, shop: ConnectedShop) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView(shop: shop, onAddShop: onAddShop) }
        case .orders:
            NavigationStack { OrdersView(shop: shop) }
        case .customers:
            NavigationStack { CustomersView(shop: shop) }
        case .reports:
            NavigationStack { ReportsView(shop: shop) }
        case .more:
            NavigationStack { MoreView(shop: shop) }
        }
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
