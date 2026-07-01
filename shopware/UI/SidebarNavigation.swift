import SwiftUI

/// Every primary destination in the app, flattened for the macOS sidebar (no "More" bucket).
/// `requiredScope` gates a row on the connected login's read access; nil = always visible.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case home, orders, customers, reports          // Overview
    case products, promotions, media, reviews       // Catalog

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .orders: "Orders"
        case .customers: "Customers"
        case .reports: "Reports"
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
        case .home: nil
        }
    }
}

/// The two sidebar sections, in order.
enum SidebarGroup: String, CaseIterable, Identifiable {
    case overview, catalog
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .catalog: "Catalog"
        }
    }

    var destinations: [Destination] {
        switch self {
        case .overview: [.home, .orders, .customers, .reports]
        case .catalog: [.products, .promotions, .media, .reviews]
        }
    }
}

#if os(macOS)
/// The macOS-native shell: a two-column `NavigationSplitView` with a grouped sidebar (shop switcher
/// on top, Overview/Catalog sections below) and a per-destination `NavigationStack` in the content
/// column. Liquid Glass rides on the split view's navigation layer automatically.
struct SidebarNavigation: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let onAddShop: () -> Void

    @State private var selection: Destination = .home
    /// A fresh navigation path per destination, so switching sidebar rows resets the pushed stack.
    @State private var paths: [Destination: [String]] = [:]
    @State private var showingManageShops = false

    private var visibleGroups: [(group: SidebarGroup, items: [Destination])] {
        SidebarGroup.allCases.compactMap { group in
            let items = group.destinations.filter { canShow($0) }
            return items.isEmpty ? nil : (group, items)
        }
    }

    private func canShow(_ dest: Destination) -> Bool {
        guard let scope = dest.requiredScope else { return true }
        return shop.canRead(scope)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visibleGroups, id: \.group.id) { entry in
                    Section(entry.group.title) {
                        ForEach(entry.items) { dest in
                            Label(dest.title, systemImage: dest.symbol)
                                .tag(dest)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
            .safeAreaInset(edge: .top) {
                SidebarShopHeader(
                    shop: shop, shops: model.data.shops,
                    onAddShop: onAddShop,
                    onManageShops: { showingManageShops = true }
                )
            }
        } detail: {
            NavigationStack(path: pathBinding(for: selection)) {
                content(for: selection)
            }
            .id(selection) // keep each destination's stack independent
        }
        .onChange(of: shop.id) {
            if !canShow(selection) { selection = .home }
        }
        .onChange(of: deepLinkKey) { consumeDeepLink() }
        .onAppear { consumeDeepLink() }
        .sheet(isPresented: $showingManageShops) {
            NavigationStack { ManageShopsView() }
                .acceptsFirstMouse()
        }
    }

    /// A stable key so `.onChange` fires whenever a new deep-link arrives.
    private var deepLinkKey: String? {
        model.pendingDeepLink.map { "\($0.shopId):\($0.orderId ?? "")" }
    }

    /// Selects Home and pushes the linked order onto Home's stack, then clears the pending link.
    private func consumeDeepLink() {
        guard let link = model.pendingDeepLink else { return }
        selection = .home
        if let orderId = link.orderId {
            paths[.home] = [orderId]
        }
        model.pendingDeepLink = nil
    }

    private func pathBinding(for dest: Destination) -> Binding<[String]> {
        Binding(get: { paths[dest] ?? [] }, set: { paths[dest] = $0 })
    }

    @ViewBuilder
    private func content(for dest: Destination) -> some View {
        switch dest {
        case .home: HomeView(shop: shop, onAddShop: onAddShop)
        case .orders: OrdersView(shop: shop)
        case .customers: CustomersView(shop: shop)
        case .reports: ReportsView(shop: shop)
        case .products: ProductsView(shop: shop)
        case .promotions: PromosView(shop: shop)
        case .media: MediaView(shop: shop)
        case .reviews: ReviewInboxView(shop: shop)
        }
    }
}

/// The shop switcher pinned to the top of the sidebar (menu over the connected shops, plus
/// add/manage). Mirrors the iOS toolbar `ShopSwitcher` but styled as a sidebar header row.
private struct SidebarShopHeader: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let shops: [ConnectedShop]
    let onAddShop: () -> Void
    let onManageShops: () -> Void

    var body: some View {
        Menu {
            ForEach(shops) { s in
                Button {
                    model.selectShop(s.id)
                } label: {
                    Label(s.name, systemImage: s.id == shop.id ? "checkmark" : "storefront")
                }
            }
            Divider()
            Button { onAddShop() } label: { Label("Add shop", systemImage: "plus") }
            Button { onManageShops() } label: { Label("Manage shops", systemImage: "gearshape") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "storefront")
                    .foregroundStyle(Theme.accent)
                Text(shop.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}
#endif
