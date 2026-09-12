import SwiftUI

struct ProductPriceFields: View {
    @Binding var draft: ProductPriceDraft
    let taxRate: Double?
    let currency: String
    @Environment(\.locale) private var locale
    var body: some View {
        LabeledContent("Currency", value: currency)
        LabeledContent("Gross price") {
            TextField("Gross price", text: Binding(get: { draft.gross }, set: { draft.updateGross($0, taxRate: taxRate, locale: locale) }))
                .labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("product.price.gross")
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
        LabeledContent("Net price") {
            TextField("Net price", text: Binding(get: { draft.net }, set: { draft.updateNet($0, taxRate: taxRate, locale: locale) }))
                .labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("product.price.net")
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
        Toggle("Link gross and net prices", isOn: $draft.linked).disabled(taxRate == nil)
            .onChange(of: draft.linked) { if draft.linked { draft.updateGross(draft.gross, taxRate: taxRate, locale: locale) } }
        if let error = draft.validationError(locale: locale) { Text(error).foregroundStyle(.red) }
    }
}
