import SwiftUI

/// The "Sales today" hero, mirroring the Home hero card: revenue, +/-% delta, daily-target progress.
/// Reusable in a WidgetKit extension (drives `SalesWidget`).
struct SalesWidgetView: View {
    let state: WidgetState?

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sales today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.revenueText)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Label(state.deltaLabel, systemImage: state.deltaUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.deltaUp ? Theme.accent : .red)
                if let pct = state.targetPct {
                    ProgressView(value: pct).tint(Theme.accent)
                }
                Spacer(minLength: 0)
                Text(state.shopName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(4)
        } else {
            WidgetEmptyView()
        }
    }
}

/// Weekly total + 7-day bar chart (today highlighted) + momentum delta (drives `WeeklySalesWidget`).
struct WeeklySalesWidgetView: View {
    let state: WeeklyWidgetState?

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(.caption2).foregroundStyle(.secondary)
                        Text(state.weekTotalText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Spacer()
                    Label(state.deltaLabel, systemImage: state.deltaUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state.deltaUp ? Theme.accent : .red)
                }
                // Fixed-height bar strip: bars are already normalized 0…1, so scale by a constant
                // height (avoids GeometryReader).
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(state.bars.enumerated()), id: \.offset) { index, value in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == state.todayIndex ? Theme.accent : Theme.accent.opacity(0.3))
                            .frame(height: max(3, 44 * value))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 44, alignment: .bottom)
                Text(state.shopName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(4)
        } else {
            WidgetEmptyView()
        }
    }
}

struct WidgetEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "storefront").foregroundStyle(.secondary)
            Text("Open the app to sync").font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
