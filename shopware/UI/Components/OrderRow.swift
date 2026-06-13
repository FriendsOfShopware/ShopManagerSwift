import SwiftUI

/// A recent-order row: number + customer, state badge, amount, relative time.
struct OrderRow: View {
    let shop: ConnectedShop
    let order: RecentOrder

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(order.orderNumber)")
                    .font(.subheadline.weight(.semibold))
                Text(order.customer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(shop.fmt(order.amount, iso: order.currencyIso))
                    .font(.subheadline.weight(.semibold))
                StatusBadge(label: order.state, tone: stateTone(order.stateTechnical))
            }
        }
        .contentShape(Rectangle())
    }
}

extension ConnectedShop {
    /// Money in a per-order currency override (falls back to the shop default).
    func fmt(_ amount: Double, iso: String?) -> String {
        Format.money(amount, currencyIso: iso ?? currency, localeTag: localeCode)
    }
}
