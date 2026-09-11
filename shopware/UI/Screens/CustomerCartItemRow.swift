import SwiftUI
import ShopwareAdminAPI

struct CustomerCartItemRow: View {
    let item: SwEntity
    let shop: ConnectedShop
    let currencyIso: String?
    let onQuantity: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { description; Spacer(); total }
                VStack(alignment: .leading, spacing: 8) { description; total }
            }
            HStack {
                if item.string("type") == "product" {
                    Stepper("Quantity: \(item.int("quantity") ?? 1)", value: Binding(
                        get: { item.int("quantity") ?? 1 }, set: onQuantity
                    ), in: 1...9999)
                }
                Button("Remove item", systemImage: "trash", role: .destructive, action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.string("label") ?? String(localized: "Order item"))
            Text(shop.fmt(item.json["price"]?["unitPrice"]?.doubleValue ?? 0, iso: currencyIso))
                .foregroundStyle(.secondary)
        }
    }

    private var total: some View {
        Text(shop.fmt(item.json["price"]?["totalPrice"]?.doubleValue ?? 0, iso: currencyIso)).monospacedDigit()
    }
}
