import SwiftUI

/// The single-shop Home dashboard: sales-today hero (revenue, delta, target, week chart),
/// stat tiles, needs-attention, and recent orders. Snapshot-backed (offline-first).
struct HomeView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let onAddShop: () -> Void

    @State private var quickProductId: String?

    private var snapshot: ShopSnapshot? { model.snapshot(shop.id) }
    private var syncState: SyncState { model.syncState(shop.id) }

    var body: some View {
        List {
            if let snapshot {
                heroSection(snapshot)
                statTiles(snapshot)
                attentionSection(snapshot)
                recentOrdersSection(snapshot)
            } else if case let .error(message) = syncState {
                SyncErrorRow(message: message) { model.refresh(shop.id) }
            } else {
                Section {
                    HStack { Spacer(); ProgressView("Loading \(shop.name)…"); Spacer() }
                        .padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .principal) {
                ShopSwitcher(shop: shop, shops: model.data.shops, onAddShop: onAddShop)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.refresh(shop.id)
                } label: {
                    if syncState == .syncing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(syncState == .syncing)
            }
        }
        .refreshable { model.refresh(shop.id) }
        .navigationDestination(for: String.self) { orderId in
            OrderDetailView(shop: shop, orderId: orderId)
        }
        .sheet(item: Binding(get: { quickProductId.map(IDBox.init) }, set: { quickProductId = $0?.id })) { box in
            ProductActionSheet(shop: shop, productId: box.id)
        }
    }

    // MARK: Hero

    private func heroSection(_ snapshot: ShopSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sales today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(shop.fmt(snapshot.todayRevenue))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                    }
                    Spacer()
                    DeltaBadge(delta: Format.delta(today: snapshot.todayRevenue, yesterday: snapshot.yesterdayRevenue))
                }

                if let target = shop.dailyTarget, target > 0 {
                    let pct = min(1, max(0, snapshot.todayRevenue / target))
                    ProgressView(value: pct)
                        .tint(Theme.accent)
                    Text("\(Int(pct * 100))% of \(shop.fmt(target)) target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                WeekChart(data: snapshot.weekRevenue, labels: weekDayLabels(endEpochMs: snapshot.lastSyncEpochMs), highlight: snapshot.todayIndex)
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.accentContainer.opacity(0.4))
        }
    }

    // MARK: Stat tiles

    private func statTiles(_ snapshot: ShopSnapshot) -> some View {
        Section {
            HStack(spacing: 10) {
                StatTile(symbol: "doc.text", value: "\(snapshot.ordersToday)", label: "Orders today")
                StatTile(symbol: "clock.badge", value: "\(snapshot.openOrders)", label: "Open orders")
                StatTile(symbol: "shippingbox", value: "\(snapshot.lowStockCount)", label: "Low stock")
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Attention

    @ViewBuilder
    private func attentionSection(_ snapshot: ShopSnapshot) -> some View {
        if snapshot.unpaidOrders > 0 || !snapshot.lowStockItems.isEmpty || snapshot.pendingReviews > 0 {
            Section("Needs attention") {
                if snapshot.pendingReviews > 0 {
                    AttentionRow(
                        symbol: "star.bubble",
                        title: String(localized: "^[\(snapshot.pendingReviews) review](inflect: true) awaiting approval"),
                        subtitle: "Tap to moderate",
                        tone: .warning
                    )
                }
                if snapshot.unpaidOrders > 0 {
                    AttentionRow(
                        symbol: "creditcard",
                        title: String(localized: "^[\(snapshot.unpaidOrders) order](inflect: true) unpaid"),
                        subtitle: "Payment open 3+ days",
                        tone: .error
                    )
                }
                ForEach(snapshot.lowStockItems) { item in
                    let actionable = !item.id.isEmpty
                    AttentionRow(
                        symbol: "shippingbox",
                        title: item.name,
                        subtitle: actionable ? "Tap to restock" : "Stock running low",
                        badge: "\(item.stock) left",
                        tone: .error,
                        action: actionable ? { quickProductId = item.id } : nil
                    )
                }
            }
        }
    }

    // MARK: Recent orders

    private func recentOrdersSection(_ snapshot: ShopSnapshot) -> some View {
        Section("Recent orders") {
            if snapshot.recentOrders.isEmpty {
                Text("No orders yet").foregroundStyle(.secondary)
            }
            ForEach(snapshot.recentOrders) { order in
                NavigationLink(value: order.id) {
                    OrderRow(shop: shop, order: order)
                }
            }
        }
    }
}

/// Needs-attention row with a tinted leading symbol.
struct AttentionRow: View {
    let symbol: String
    let title: String
    let subtitle: LocalizedStringKey
    var badge: String? = nil
    var tone: BadgeTone = .error
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tone.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let badge {
                Text(badge).font(.caption.weight(.semibold)).foregroundStyle(tone.color)
            }
        }
        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct SyncErrorRow: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

/// Toolbar shop switcher (Menu over the connected shops).
struct ShopSwitcher: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let shops: [ConnectedShop]
    let onAddShop: () -> Void

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
            NavigationLink { ManageShopsView() } label: { Label("Manage shops", systemImage: "gearshape") }
        } label: {
            HStack(spacing: 4) {
                Text(shop.name).font(.headline)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
    }
}

/// Identifiable wrapper so a plain String id drives a `.sheet(item:)`.
struct IDBox: Identifiable { let id: String }
