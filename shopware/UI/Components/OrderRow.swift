import SwiftUI

/// A native order list row: number + customer on the left, amount + state on the right.
struct OrderRow: View {
    let shop: ConnectedShop
    let order: RecentOrder

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(order.orderNumber)")
                    .font(.body)
                Text(order.customer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(shop.fmt(order.amount, iso: order.currencyIso))
                    .font(.body.weight(.semibold))
                StatusBadge(label: order.state, tone: stateTone(order.stateTechnical))
            }
        }
    }
}

extension ConnectedShop {
    /// Money in a per-order currency override (falls back to the shop default).
    func fmt(_ amount: Double, iso: String?) -> String {
        Format.money(amount, currencyIso: iso ?? currency, localeTag: localeCode)
    }
}
