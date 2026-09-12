import SwiftUI
import ShopwareAdminAPI

struct PromotionDiscountsContent: View {
    let promotion: PromotionItem
    let actions: PromotionActions
    let edit: (PromotionDiscount?) -> Void
    let delete: (PromotionDiscount) -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        Form {
            Section {
                Button("Add discount…", systemImage: "plus") { edit(nil) }
                    .disabled(!actions.canEdit || actions.currencyCode == nil || promotion.orderCount > 0 || !actions.permissions.allows("promotion_discount:create"))
                    .accessibilityIdentifier("promotion.discounts.add")
                if promotion.orderCount > 0 { Text("Discounts cannot be changed after a promotion has been redeemed.").foregroundStyle(.secondary) }
                if promotion.discounts.isEmpty { Text("Add a discount to define how this promotion reduces the price.").foregroundStyle(.secondary) }
            }
            ForEach(promotion.discounts) { discount in
                Section {
                    LabeledContent("Type", value: discount.typeTitle)
                    LabeledContent("Value") {
                        if discount.type == "percentage" { Text("\(discount.value.formatted(.number.locale(locale)))%") }
                        else { PromotionMoneyText(amount: discount.value, currency: actions.currencyCode) }
                    }
                    if let maximum = discount.maxValue { LabeledContent("Maximum discount") { PromotionMoneyText(amount: maximum, currency: actions.currencyCode) } }
                    ForEach(discount.prices.compactMap { value -> PromotionPriceRow? in
                        guard let id = value["id"]?.stringValue else { return nil }
                        return PromotionPriceRow(id: id, currency: value["currency"]?["isoCode"]?.stringValue ?? "", amount: value["price"]?.doubleValue ?? 0)
                    }) { price in
                        LabeledContent(price.currency.isEmpty ? String(localized: "Currency override") : price.currency) {
                            if price.currency.isEmpty { Text(price.amount, format: .number) }
                            else { Text(price.amount, format: .currency(code: price.currency)) }
                        }
                    }
                    if discount.advanced {
                        LabeledContent("Product rules", value: discount.rules.map(\.name).formatted())
                        if !discount.sorter.isEmpty { LabeledContent("Product order", value: label(discount.sorter)) }
                        if !discount.applier.isEmpty { LabeledContent("Apply to", value: label(discount.applier)) }
                        if !discount.usage.isEmpty { LabeledContent("Applications", value: label(discount.usage)) }
                    }
                    HStack {
                        Button("Edit discount…", systemImage: "pencil") { edit(discount) }
                            .disabled(!actions.canEdit || actions.currencyCode == nil || promotion.orderCount > 0 || !actions.permissions.allows("promotion_discount:update"))
                            .accessibilityIdentifier("promotion.discount.edit.\(discount.id)")
                        Spacer()
                        Button("Delete discount…", systemImage: "trash", role: .destructive) { delete(discount) }
                            .tint(.red)
                            .disabled(!actions.canEdit || promotion.orderCount > 0 || !actions.permissions.allows("promotion_discount:delete"))
                    }.buttonStyle(.borderless)
                } header: { Text("\(discount.scopeTitle) discount") }
            }
        }.groupedFormStyle()
    }
    private func label(_ key: String) -> String {
        switch key {
        case "PRICE_ASC": String(localized: "Lowest price first")
        case "PRICE_DESC": String(localized: "Highest price first")
        case "ALL": String(localized: "All eligible items")
        default: key
        }
    }
}
private struct PromotionPriceRow: Identifiable { let id: String; let currency: String; let amount: Double }
