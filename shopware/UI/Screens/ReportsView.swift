import SwiftUI

/// Reports: 7-day revenue (total + momentum delta + chart), top products, and a cross-shop
/// revenue comparison. Snapshot-backed, like Home.
struct ReportsView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop

    private var snapshot: ShopSnapshot? { model.snapshot(shop.id) }

    var body: some View {
        List {
            if let snapshot {
                revenueSection(snapshot)
                topProductsSection(snapshot)
                crossShopSection()
            } else {
                Text("Sync this shop to see reports.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Reports")
    }

    private func revenueSection(_ snapshot: ShopSnapshot) -> some View {
        let total = snapshot.weekRevenue.reduce(0, +)
        let firstHalf = snapshot.weekRevenue.prefix(3).reduce(0, +)
        let secondHalf = snapshot.weekRevenue.suffix(3).reduce(0, +)
        return Section("Revenue · 7 days") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shop.fmt(total))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Spacer()
                    DeltaBadge(delta: Format.delta(today: secondHalf, yesterday: firstHalf))
                }
                WeekChart(
                    data: snapshot.weekRevenue,
                    labels: weekDayLabels(endEpochMs: snapshot.lastSyncEpochMs),
                    highlight: snapshot.todayIndex
                )
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func topProductsSection(_ snapshot: ShopSnapshot) -> some View {
        if !snapshot.topProducts.isEmpty {
            let maxRevenue = snapshot.topProducts.map(\.revenue).max() ?? 1
            Section("Top products · 7 days") {
                ForEach(snapshot.topProducts) { product in
                    RankBar(
                        title: product.name,
                        detail: "\(product.quantity) sold",
                        value: shop.fmt(product.revenue),
                        fraction: maxRevenue > 0 ? product.revenue / maxRevenue : 0
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func crossShopSection() -> some View {
        let others = model.data.shops.filter { model.snapshot($0.id) != nil }
        if others.count > 1 {
            let maxToday = others.map { model.snapshot($0.id)?.todayRevenue ?? 0 }.max() ?? 1
            Section("Today across shops") {
                ForEach(others) { s in
                    let today = model.snapshot(s.id)?.todayRevenue ?? 0
                    RankBar(
                        title: s.name,
                        detail: nil,
                        value: s.fmt(today),
                        fraction: maxToday > 0 ? today / maxToday : 0,
                        tint: s.tint.lightBg
                    )
                }
            }
        }
    }
}

/// A labeled horizontal proportion bar (top-products / cross-shop comparison).
struct RankBar: View {
    let title: String
    var detail: String?
    let value: String
    let fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).lineLimit(1)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15)).frame(height: 6)
                    Capsule().fill(tint).frame(width: max(4, geo.size.width * fraction), height: 6)
                }
            }
            .frame(height: 6)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
