import ShopwareDomain
import SwiftUI
import ShopwareAdminAPI

struct ProductPriceEditorSheet: View {
    let product: ProductItem
    let currency: ProductCurrency
    let actions: ProductActions
    let onSave: () -> Void
    @Environment(\.locale) private var locale
    @State private var draft: ProductPriceDraft
    @State private var original: ProductPriceDraft
    init(product: ProductItem, currency: ProductCurrency, actions: ProductActions, onSave: @escaping () -> Void) {
        self.product = product; self.currency = currency; self.actions = actions; self.onSave = onSave
        let draft = ProductPriceDraft(price: product.prices.first { $0["currencyId"]?.stringValue == currency.id }, currencyID: currency.id, locale: Locale.current)
        _draft = State(initialValue: draft); _original = State(initialValue: draft)
    }
    var body: some View {
        EntityEditorSheet(title: "Edit price", identifier: "product", busy: actions.busy, changed: draft != original,
                          canSave: actions.canEdit && draft != original && draft.validationError(locale: locale) == nil, error: actions.error, idealHeight: 400) {
            let saved = await actions.savePrice(product, draft: draft, locale: locale)
            if saved { onSave() }; return saved
        } content: {
            Section { Text(product.name).font(.headline); Text(product.productNumber).foregroundStyle(.secondary) }
            Section { ProductPriceFields(draft: $draft, taxRate: product.taxRate, currency: currency.code) }
            if product.isVariant { Section { Text("Saving creates a price override for this variant.").foregroundStyle(.secondary) } }
        }.onAppear { actions.error = nil }
    }
}
