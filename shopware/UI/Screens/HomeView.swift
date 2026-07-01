import SwiftUI

/// The single-shop Home dashboard in the Settings/Mail language: an inset-grouped list with a
/// Today section (revenue + delta + target + week chart), quick stats, needs-attention, and recent
/// orders. Snapshot-backed (offline-first).
struct HomeView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let onAddShop: () -> Void

    @State private var quickProductId: String?
    #if os(macOS)
    @State private var pushedOrderId: String?
    #endif

    private var snapshot: ShopSnapshot? { model.snapshot(shop.id) }
    private var syncState: SyncState { model.syncState(shop.id) }

    var body: some View {
        content
        .navigationTitle("Home")
        .toolbar {
            #if os(iOS)
            // On macOS the shop switcher lives in the sidebar header instead.
            ToolbarItem(placement: .principal) {
                ShopSwitcher(shop: shop, shops: model.data.shops, onAddShop: onAddShop)
            }
            #endif
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
        #if os(macOS)
        .navigationDestination(item: $pushedOrderId) { orderId in
            OrderDetailView(shop: shop, orderId: orderId)
        }
        #endif
        .sheet(item: Binding(get: { quickProductId.map(IDBox.init) }, set: { quickProductId = $0?.id })) { box in
            ProductActionSheet(shop: shop, productId: box.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macDashboard
        #else
        iosList
        #endif
    }

    // MARK: iOS — inset-grouped list

    private var iosList: some View {
        List {
            if let snapshot {
                todaySection(snapshot)
                statsSection(snapshot)
                attentionSection(snapshot)
                recentOrdersSection(snapshot)
            } else if case let .error(message) = syncState {
                SyncErrorRow(message: message) { model.refresh(shop.id) }
            } else {
                Section {
                    HStack { Spacer(); ProgressView("Loading \(shop.name)…"); Spacer() }
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .groupedListStyle()
    }

    // MARK: macOS — dashboard grid

    #if os(macOS)
    @ViewBuilder
    private var macDashboard: some View {
        if let snapshot {
            HomeDashboard(
                shop: shop,
                snapshot: snapshot,
                onOpenOrder: { pushedOrderId = $0 },
                onRestock: { quickProductId = $0 }
            )
        } else if case let .error(message) = syncState {
            ContentUnavailableView {
                Label("Sync failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { model.refresh(shop.id) }.buttonStyle(.glassProminent)
            }
        } else {
            ProgressView("Loading \(shop.name)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    #endif

    // MARK: Today

    private func todaySection(_ snapshot: ShopSnapshot) -> some View {
        Section {
            // Revenue as a prominent value row, with the trend trailing.
            HStack(alignment: .firstTextBaseline) {
                Text(shop.fmt(snapshot.todayRevenue))
                    .font(.largeTitle.weight(.bold))
                    .contentTransition(.numericText())
                Spacer()
                DeltaBadge(delta: Format.delta(today: snapshot.todayRevenue, yesterday: snapshot.yesterdayRevenue))
            }

            if let target = shop.dailyTarget, target > 0 {
                let pct = min(1, max(0, snapshot.todayRevenue / target))
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: pct).tint(Theme.accent)
                    Text("\(Int(pct * 100))% of \(shop.fmt(target)) target")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            WeekChart(
                data: snapshot.weekRevenue,
                labels: weekDayLabels(endEpochMs: snapshot.lastSyncEpochMs),
                highlight: snapshot.todayIndex
            )
            .padding(.vertical, 4)
        } header: {
            Text("Sales today")
        }
    }

    // MARK: Quick stats

    private func statsSection(_ snapshot: ShopSnapshot) -> some View {
        Section {
            MetricRow(symbol: "doc.text", label: "Orders today", value: "\(snapshot.ordersToday)")
            MetricRow(symbol: "clock.badge", label: "Open orders", value: "\(snapshot.openOrders)")
            MetricRow(symbol: "shippingbox", label: "Low stock", value: "\(snapshot.lowStockCount)", tint: snapshot.lowStockCount > 0 ? .orange : Theme.accent)
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
                        title: "^[\(snapshot.pendingReviews) review](inflect: true) awaiting approval",
                        subtitle: "Tap to moderate",
                        tone: .warning
                    )
                }
                if snapshot.unpaidOrders > 0 {
                    AttentionRow(
                        symbol: "creditcard",
                        title: "^[\(snapshot.unpaidOrders) order](inflect: true) unpaid",
                        subtitle: "Payment open 3+ days",
                        tone: .error
                    )
                }
                ForEach(snapshot.lowStockItems) { item in
                    let actionable = !item.id.isEmpty
                    AttentionRow(
                        symbol: "shippingbox",
                        title: "\(item.name)",
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

/// Needs-attention row: leading tinted symbol, title + subtitle, optional trailing badge. Tappable
/// rows show a disclosure chevron (NavigationLink-style) via the Button.
struct AttentionRow: View {
    let symbol: String
    /// A `LocalizedStringResource` so automatic grammar agreement (`^[…](inflect: true)`) resolves
    /// at render time; `String(localized:)` would strip the markup unresolved here.
    let title: LocalizedStringResource
    let subtitle: LocalizedStringKey
    var badge: String? = nil
    var tone: BadgeTone = .error
    var action: (() -> Void)? = nil

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tone.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let badge {
                Text(badge).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
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
            ContentUnavailableView {
                Label("Sync failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry", action: onRetry).buttonStyle(.glass)
            }
            .listRowBackground(Color.clear)
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
