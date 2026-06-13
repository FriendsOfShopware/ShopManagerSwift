import SwiftUI

/// Reports: 7-day revenue (total + momentum delta + chart), top products, and a cross-shop revenue
/// comparison — all as grouped-list sections (Settings/Mail language).
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
                ContentUnavailableView("No data yet", systemImage: "chart.bar",
                                       description: Text("Sync this shop to see reports."))
                    .listRowBackground(Color.clear)
            }
        }
        .groupedListStyle()
        .navigationTitle("Reports")
    }

    private func revenueSection(_ snapshot: ShopSnapshot) -> some View {
        let total = snapshot.weekRevenue.reduce(0, +)
        let firstHalf = snapshot.weekRevenue.prefix(3).reduce(0, +)
        let secondHalf = snapshot.weekRevenue.suffix(3).reduce(0, +)
        return Section {
            HStack(alignment: .firstTextBaseline) {
                Text(shop.fmt(total))
                    .font(.largeTitle.weight(.bold))
                Spacer()
                DeltaBadge(delta: Format.delta(today: secondHalf, yesterday: firstHalf))
            }
            WeekChart(
                data: snapshot.weekRevenue,
                labels: weekDayLabels(endEpochMs: snapshot.lastSyncEpochMs),
                highlight: snapshot.todayIndex
            )
            .padding(.vertical, 4)
        } header: {
            Text("Revenue · 7 days")
        }
    }

    @ViewBuilder
    private func topProductsSection(_ snapshot: ShopSnapshot) -> some View {
        if !snapshot.topProducts.isEmpty {
            Section("Top products · 7 days") {
                ForEach(Array(snapshot.topProducts.enumerated()), id: \.element.id) { index, product in
                    RankRow(
                        rank: index + 1,
                        title: product.name,
                        detail: "^[\(product.quantity) sold](inflect: true)",
                        value: shop.fmt(product.revenue)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func crossShopSection() -> some View {
        let others = model.data.shops.filter { model.snapshot($0.id) != nil }
        if others.count > 1 {
            Section("Today across shops") {
                ForEach(others) { s in
                    let today = model.snapshot(s.id)?.todayRevenue ?? 0
                    HStack {
                        ShopTintDot(tint: s.tint)
                        Text(s.name).lineLimit(1)
                        Spacer()
                        Text(s.fmt(today)).font(.body.weight(.semibold))
                    }
                }
            }
        }
    }
}

/// A ranked list row: rank number, title + secondary detail, bold trailing value.
struct RankRow: View {
    let rank: Int
    let title: String
    let detail: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.body.weight(.semibold))
        }
    }
}
