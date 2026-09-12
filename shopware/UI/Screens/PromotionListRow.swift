import SwiftUI

struct PromotionListRow: View {
    let promotion: PromotionItem
    let currency: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(promotion.name).font(.headline).foregroundStyle(.primary)
            ViewThatFits(in: .horizontal) {
                HStack { PromotionStatusLabel(state: promotion.state()); Text("·"); Text(promotion.codeMode.title) }
                VStack(alignment: .leading, spacing: 4) { PromotionStatusLabel(state: promotion.state()); Text(promotion.codeMode.title) }
            }.font(.callout).foregroundStyle(.secondary)
            PromotionDiscountText(discounts: promotion.discounts, currency: currency).font(.callout).foregroundStyle(.secondary)
            Text("\(promotion.orderCount) redemptions").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
    }
}
