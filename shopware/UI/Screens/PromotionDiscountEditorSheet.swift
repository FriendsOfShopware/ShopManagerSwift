import SwiftUI

struct PromotionDiscountEditorSheet: View {
    let promotion: PromotionItem
    let discount: PromotionDiscount?
    @Bindable var actions: PromotionActions
    let onSave: () -> Void
    @Environment(\.locale) private var locale
    @State private var draft = PromotionDiscountDraft(locale: .current)
    @State private var original = PromotionDiscountDraft(locale: .current)
    @State private var seeded = false
    @State private var id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    var body: some View {
        PromotionFormSheet(title: discount == nil ? "Add discount" : "Edit discount", busy: actions.busy,
                           changed: draft != original, canSave: (discount == nil || draft != original) && actions.canEdit && actions.currencyCode != nil && draft.validationError(locale: locale) == nil,
                           error: actions.error, idealHeight: 430) {
            let success = await actions.saveDiscount(promotion: promotion, discount: discount, id: discount?.id ?? id, draft: draft, locale: locale)
            if success { onSave() }
            return success
        } content: {
            Section("Discount") {
                if let discount {
                    LabeledContent("Applies to", value: discount.scopeTitle)
                    LabeledContent("Type", value: discount.typeTitle)
                } else {
                    Picker("Applies to", selection: $draft.scope) { Text("Cart").tag("cart"); Text("Shipping").tag("delivery") }
                    Picker("Type", selection: $draft.type) { Text("Percentage").tag("percentage"); Text("Amount off").tag("absolute"); if draft.scope != "cart" { Text("Fixed price").tag("fixed") }; if draft.scope != "delivery" { Text("Fixed unit price").tag("fixed_unit") } }
                }
                LabeledContent(draft.type == "percentage" ? String(localized: "Percentage") : actions.currencyCode ?? String(localized: "Value")) {
                    TextField("Value", text: $draft.value).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.discount.value")
                }
                if draft.type == "percentage" {
                    LabeledContent("Maximum discount") { TextField("Unlimited", text: $draft.maximum).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.discount.maximum") }
                }
                if discount?.prices.isEmpty == false { Text("Currency overrides remain in effect for their assigned currencies.").font(.callout).foregroundStyle(.secondary) }
            }
            if let error = draft.validationError(locale: locale) { Section { Text(error).foregroundStyle(.red) } }
        }
        .onChange(of: draft.scope) { if draft.scope == "delivery" && draft.type == "fixed_unit" { draft.type = "fixed" }; if draft.scope == "cart" && draft.type == "fixed" { draft.type = "fixed_unit" } }
        .onAppear {
            if !seeded { draft = PromotionDiscountDraft(discount, locale: locale); original = draft; seeded = true }
            actions.error = nil
        }
    }
}
