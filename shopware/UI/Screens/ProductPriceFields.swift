import ShopwareDomain
import SwiftUI

struct ProductPriceFields: View {
    @Binding var draft: ProductPriceDraft
    let taxRate: Double?
    let currency: String
    @Environment(\.locale) private var locale
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private enum Field: Hashable { case gross, net }
    @FocusState private var focusedField: Field?
    #endif

    var body: some View {
        LabeledContent("Currency", value: currency)
        LabeledContent("Gross price") {
            TextField("Gross price", text: Binding(get: { draft.gross }, set: { draft.updateGross($0, taxRate: taxRate, locale: locale) }))
                .labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("product.price.gross")
                #if os(iOS)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .gross)
                #endif
        }
        #if os(iOS)
        .toolbar {
            if horizontalSizeClass == .compact, focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("product.price.done")
                }
            }
        }
        #endif
        LabeledContent("Net price") {
            TextField("Net price", text: Binding(get: { draft.net }, set: { draft.updateNet($0, taxRate: taxRate, locale: locale) }))
                .labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("product.price.net")
                #if os(iOS)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .net)
                #endif
        }
        Toggle("Link gross and net prices", isOn: $draft.linked).disabled(taxRate == nil)
            .onChange(of: draft.linked) { if draft.linked { draft.updateGross(draft.gross, taxRate: taxRate, locale: locale) } }
        if let error = draft.validationError(locale: locale) { Text(error).foregroundStyle(.red) }
    }
}
