#if os(macOS)
import SwiftUI

/// The macOS Home dashboard: a wide hero card (revenue + target + week chart), a row of stat cards,
/// and a two-column Needs-attention / Recent-orders grid — using the full window width instead of a
/// narrow inset-grouped list. iOS keeps the List layout in `HomeView`.
struct HomeDashboard: View {
    let shop: ConnectedShop
    let snapshot: ShopSnapshot
    let onOpenOrder: (String) -> Void
    let onRestock: (String) -> Void

    private var hasAttention: Bool {
        snapshot.unpaidOrders > 0 || !snapshot.lowStockItems.isEmpty || snapshot.pendingReviews > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                statCards

                // Two columns when there's attention to show; otherwise recent orders spans full width.
                if hasAttention {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            attentionCard.frame(maxWidth: .infinity, alignment: .top)
                            recentOrdersCard.frame(maxWidth: .infinity, alignment: .top)
                        }
                        VStack(spacing: 16) { attentionCard; recentOrdersCard }
                    }
                } else {
                    recentOrdersCard
                }
            }
            .padding(20)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Hero

    private var hero: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sales today")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(shop.fmt(snapshot.todayRevenue))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                    }
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
                .frame(height: 160)
            }
        }
    }

    // MARK: Stat cards

    private var statCards: some View {
        HStack(spacing: 16) {
            StatCard(symbol: "doc.text", label: "Orders today",
                     value: "\(snapshot.ordersToday)", tint: Theme.accent)
            StatCard(symbol: "clock.badge", label: "Open orders",
                     value: "\(snapshot.openOrders)", tint: Theme.accent)
            StatCard(symbol: "shippingbox", label: "Low stock",
                     value: "\(snapshot.lowStockCount)",
                     tint: snapshot.lowStockCount > 0 ? .orange : Theme.accent)
        }
    }

    // MARK: Needs attention

    private var attentionCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Needs attention").font(.headline)

                if snapshot.pendingReviews > 0 {
                    AttentionRow(
                        symbol: "star.bubble",
                        title: String(localized: "^[\(snapshot.pendingReviews) review](inflect: true) awaiting approval"),
                        subtitle: "Open Reviews to moderate",
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
                        subtitle: actionable ? "Click to restock" : "Stock running low",
                        badge: "\(item.stock) left",
                        tone: .error,
                        action: actionable ? { onRestock(item.id) } : nil
                    )
                }
            }
        }
    }

    // MARK: Recent orders

    private var recentOrdersCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent orders").font(.headline)
                if snapshot.recentOrders.isEmpty {
                    Text("No orders yet").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(Array(snapshot.recentOrders.enumerated()), id: \.element.id) { index, order in
                        Button { onOpenOrder(order.id) } label: {
                            OrderRow(shop: shop, order: order)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < snapshot.recentOrders.count - 1 { Divider() }
                    }
                }
            }
        }
    }
}

/// A single stat as a compact card: leading tinted glyph, big value, caption label.
private struct StatCard: View {
    let symbol: String
    let label: LocalizedStringKey
    let value: String
    var tint: Color = Theme.accent

    var body: some View {
        DashboardCard {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A rounded, subtly-filled container that reads as a dashboard "card" on macOS.
struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            }
    }
}
#endif
