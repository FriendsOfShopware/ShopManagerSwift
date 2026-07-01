import SwiftUI
import Charts

/// The live Analytics/Reports tab: 12 KPIs (trend charts, top-N breakdowns, a single number),
/// driven by a shared date-range + multi-dimension filter bar, plus a period-aware cross-shop
/// comparison. Ports the Android Analytics feature (SwagAnalytics-modeled).
struct ReportsView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop

    @State private var vm: ReportsViewModel?
    @State private var showingFilters = false

    private let trendKPIs: [KpiType] = [.totalSales, .orderCount, .avgOrderValue, .newCustomers]
    private let breakdownKPIs: [KpiType] = [
        .salesChannel, .paymentMethod, .shippingMethod, .country,
        .bestSellingProduct, .manufacturer, .promotionCode,
    ]

    var body: some View {
        Group {
            if let vm {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFilters = true
                } label: {
                    Label("Filters", systemImage: (vm?.filters.activeCount ?? 0) > 0
                        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .badge(vm?.filters.activeCount ?? 0)
            }
        }
        .sheet(isPresented: $showingFilters) {
            if let vm {
                AnalyticsFilterSheet(
                    options: vm.options ?? .init(),
                    filters: vm.filters,
                    onApply: { vm.applyFilters($0) }
                )
            }
        }
        .onAppear {
            if vm == nil { vm = ReportsViewModel(repo: model.repo) }
            vm?.start(shop, allShops: model.data.shops)
        }
        .onChange(of: shop.id) { vm?.start(shop, allShops: model.data.shops) }
    }

    private func content(_ vm: ReportsViewModel) -> some View {
        List {
            Section {
                DateRangeBar(preset: vm.filters.dateRange.preset) { vm.setPreset($0) }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            ForEach(trendKPIs) { type in
                Section(type.title) {
                    kpiCard(type, vm: vm)
                }
            }

            Section(KpiType.customerCount.title) {
                kpiCard(.customerCount, vm: vm)
            }

            ForEach(breakdownKPIs) { type in
                Section(type.title) {
                    kpiCard(type, vm: vm)
                }
            }

            crossShopSection(vm)
        }
        .groupedListStyle()
    }

    @ViewBuilder
    private func kpiCard(_ type: KpiType, vm: ReportsViewModel) -> some View {
        switch vm.kpiStates[type] ?? .loading {
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 8)
        case let .error(message):
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { vm.retry(type) }
            }
        case let .timeSeries(kpi):
            TrendCard(shop: shop, kpi: kpi)
        case let .breakdown(kpi):
            BreakdownCard(shop: shop, kpi: kpi)
        case let .single(kpi):
            SingleNumberCard(shop: shop, kpi: kpi)
        }
    }

    @ViewBuilder
    private func crossShopSection(_ vm: ReportsViewModel) -> some View {
        let others = model.data.shops.filter { vm.shopRevenues.keys.contains($0.id) }
        if others.count > 1 {
            let maxRev = others.compactMap { vm.shopRevenues[$0.id] ?? nil }.max() ?? 1
            Section("Revenue across shops") {
                ForEach(others) { s in
                    let rev = vm.shopRevenues[s.id] ?? nil
                    HStack {
                        ShopTintDot(tint: s.tint)
                        Text(s.name).lineLimit(1)
                        Spacer()
                        if let rev {
                            Text(s.fmt(rev)).font(.body.weight(.semibold))
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let rev, maxRev > 0 {
                        ProgressView(value: max(0, rev), total: maxRev)
                            .tint(s.tint.lightBg)
                    }
                }
            }
        }
    }
}

/// The Today/7/30/90 preset selector.
private struct DateRangeBar: View {
    let preset: DateRange.Preset
    let onSelect: (DateRange.Preset) -> Void

    var body: some View {
        Picker("Range", selection: Binding(get: { preset }, set: { onSelect($0) })) {
            ForEach([DateRange.Preset.today, .last7, .last30, .last90]) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// A time-series KPI: headline total + prior-period delta + a line/bar chart.
private struct TrendCard: View {
    let shop: ConnectedShop
    let kpi: TimeSeriesKpi

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.title2.weight(.bold))
                Spacer()
                if let prev = kpi.previousTotal {
                    DeltaBadge(delta: Format.delta(today: kpi.total, yesterday: prev))
                }
            }
            if kpi.points.contains(where: { $0.value != 0 }) {
                Chart(kpi.points) { point in
                    LineMark(
                        x: .value("Date", Date(timeIntervalSince1970: Double(point.epochMs) / 1000)),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
                    AreaMark(
                        x: .value("Date", Date(timeIntervalSince1970: Double(point.epochMs) / 1000)),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Theme.accent.opacity(0.12))
                    .interpolationMethod(.monotone)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 120)
            } else {
                Text("No data in this period").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var headline: String {
        kpi.isMoney ? shop.fmt(kpi.total) : "\(Int(kpi.total))"
    }
}

/// A top-N breakdown KPI as ranked rows with a proportion bar.
private struct BreakdownCard: View {
    let shop: ConnectedShop
    let kpi: BreakdownKpi

    var body: some View {
        if kpi.rows.isEmpty {
            Text("No data in this period").font(.caption).foregroundStyle(.secondary)
        } else {
            let maxValue = kpi.rows.map(\.value).max() ?? 1
            ForEach(kpi.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label).lineLimit(1)
                        Spacer()
                        Text(valueText(row.value)).font(.subheadline.weight(.semibold))
                    }
                    ProgressView(value: max(0, row.value), total: maxValue)
                        .tint(Theme.accent)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func valueText(_ value: Double) -> String {
        kpi.valueIsMoney ? shop.fmt(value) : "\(Int(value))"
    }
}

/// A single cumulative number KPI with a delta vs the previous window.
private struct SingleNumberCard: View {
    let shop: ConnectedShop
    let kpi: SingleKpi

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kpi.isMoney ? shop.fmt(kpi.value) : "\(Int(kpi.value))")
                .font(.title2.weight(.bold))
            Spacer()
            if let prev = kpi.previousValue {
                DeltaBadge(delta: Format.delta(today: kpi.value, yesterday: prev))
            }
        }
    }
}
