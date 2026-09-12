import SwiftUI
import ShopwareAdminAPI

struct ProductPricesContent: View {
    let product: ProductItem
    let actions: ProductActions
    let shop: ConnectedShop
    let edit: (ProductCurrency) -> Void
    var body: some View {
        Form {
            if shop.productFields.showPrice {
                Section("Tax") {
                    LabeledContent("Tax rate") {
                        if let rate = product.taxRate { Text(rate, format: .percent.scale(1)) } else { Text("—") }
                    }
                }
                ForEach(actions.currencies) { currency in
                    let price = product.prices.first { $0["currencyId"]?.stringValue == currency.id }
                    Section(currency.code) {
                        if let price {
                            LabeledContent("Gross price") { ProductMoneyText(amount: price["gross"]?.doubleValue, currency: currency.code) }
                            LabeledContent("Net price") { ProductMoneyText(amount: price["net"]?.doubleValue, currency: currency.code) }
                            if let amount = price["listPrice"]?["gross"]?.doubleValue { LabeledContent("List price") { ProductMoneyText(amount: amount, currency: currency.code) } }
                            if let amount = price["regulationPrice"]?["gross"]?.doubleValue { LabeledContent("Lowest price in the last 30 days") { ProductMoneyText(amount: amount, currency: currency.code) } }
                        } else { Text("No explicit price in this currency").foregroundStyle(.secondary) }
                        if shop.productFields.editPrice {
                            Button(price == nil ? "Set price…" : "Edit price…", systemImage: "pencil") { edit(currency) }
                                .disabled(!actions.canEdit || actions.currencyCode == nil).accessibilityIdentifier("product.price.edit." + currency.id)
                        }
                    }
                }
                Section("Advanced prices") {
                    if product.advancedPrices.isEmpty { Text("No rule-based prices").foregroundStyle(.secondary) }
                    ForEach(product.advancedPrices.compactMap { $0["id"]?.stringValue }, id: \.self) { id in
                        if let price = product.advancedPrices.first(where: { $0["id"]?.stringValue == id }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(price["rule"]?["name"]?.stringValue ?? String(localized: "Pricing rule")).fontWeight(.medium)
                                if let start = price["quantityStart"]?.intValue {
                                    if let end = price["quantityEnd"]?.intValue { Text("Quantity \(start)–\(end)").foregroundStyle(.secondary) }
                                    else { Text("Quantity \(start) and above").foregroundStyle(.secondary) }
                                }
                                ProductMoneyText(amount: price["price"]?.arrayValue?.first { $0["currencyId"]?.stringValue == ShopwareDefaults.currencyID }?["gross"]?.doubleValue, currency: actions.currencyCode)
                            }
                        }
                    }
                }
            } else { Section { Text("Prices are hidden in this shop's display settings.").foregroundStyle(.secondary) } }
        }.groupedFormStyle().accessibilityIdentifier("product.prices")
    }
}
