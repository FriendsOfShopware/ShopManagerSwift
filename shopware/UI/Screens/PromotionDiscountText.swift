import SwiftUI

struct PromotionDiscountText: View {
    let discounts: [PromotionDiscount]
    let currency: String?
    @Environment(\.locale) private var locale
    var body: some View {
        if let discount = discounts.first {
            if discounts.count > 1 { Text("\(discounts.count) discounts") }
            else if discount.type == "percentage" { Text("\(discount.value.formatted(.number.locale(locale)))% off") }
            else if discount.type == "absolute" { Text("\(amount(discount.value)) off") }
            else { Text("\(discount.typeTitle): \(amount(discount.value))") }
        } else { Text("No discounts") }
    }
    private func amount(_ value: Double) -> String {
        if let currency { return value.formatted(.currency(code: currency).locale(locale)) }
        return value.formatted(.number.locale(locale))
    }
}
