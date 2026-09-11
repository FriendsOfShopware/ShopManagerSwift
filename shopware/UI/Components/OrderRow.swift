import SwiftUI

/// A native order list row: number + customer on the left, amount + state on the right.
struct OrderRow: View {
    let shop: ConnectedShop
    let order: RecentOrder
    var showsCustomer = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(order.orderNumber)")
                    .font(.body)
                Group {
                    if showsCustomer {
                        Text(order.customer)
                    } else {
                        Text(Date(timeIntervalSince1970: Double(order.placedMs) / 1000), format: .dateTime.day().month().year())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
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
