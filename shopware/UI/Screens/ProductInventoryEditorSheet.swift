import SwiftUI
import ShopwareAdminAPI

struct ProductInventoryEditorSheet: View {
    let product: ProductItem
    let actions: ProductActions
    let onSave: () -> Void
    @Environment(\.locale) private var locale
    @State private var draft: ProductInventoryDraft
    @State private var original: ProductInventoryDraft
    @State private var selecting: ProductInventoryRelation?
    init(product: ProductItem, actions: ProductActions, onSave: @escaping () -> Void) {
        self.product = product; self.actions = actions; self.onSave = onSave
        let value = ProductInventoryDraft(product, locale: Locale.current)
        _draft = State(initialValue: value); _original = State(initialValue: value)
    }
    var body: some View {
        EntityEditorSheet(title: "Edit inventory", identifier: "product", busy: actions.busy, changed: draft != original,
                          canSave: actions.canEdit && draft != original && draft.validationError(locale: locale) == nil, error: actions.error) {
            let saved = await actions.saveInventory(product, draft: draft, locale: locale)
            if saved { onSave() }; return saved
        } content: {
            Section("Stock") {
                number(.stock)
                Toggle("Clearance sale", isOn: $draft.closeout)
                Text("Clearance products cannot be purchased once stock is exhausted.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Delivery") {
                Button { selecting = .deliveryTime } label: { LabeledContent("Delivery time", value: draft.deliveryTimeID.isEmpty ? String(localized: "None") : String(localized: "1 selected")) }
                    .disabled(!actions.permissions.allows("delivery_time:read"))
                number(.restockTime)
                Toggle("Free shipping", isOn: $draft.shippingFree)
                Toggle("Set a release date", isOn: Binding(get: { draft.releaseDate != nil }, set: { draft.releaseDate = $0 ? Date() : nil }))
                if draft.releaseDate != nil { DatePicker("Release date", selection: Binding(get: { draft.releaseDate ?? Date() }, set: { draft.releaseDate = $0 })) }
            }
            Section("Purchase limits") { number(.minPurchase); number(.purchaseSteps); number(.maxPurchase) }
            Section("Measurements") { number(.weight); number(.width); number(.height); number(.length) }
            Section("Packaging") {
                Button { selecting = .unit } label: { LabeledContent("Unit", value: draft.unitID.isEmpty ? String(localized: "None") : String(localized: "1 selected")) }
                    .disabled(!actions.permissions.allows("unit:read"))
                number(.purchaseUnit); number(.referenceUnit)
                TextField("Pack unit", text: $draft.packUnit)
                TextField("Pack unit (plural)", text: $draft.packUnitPlural)
            }
            if let error = draft.validationError(locale: locale) { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("product.validationError") } }
        }.onAppear { actions.error = nil }
        .sheet(item: $selecting) { relation in
            CustomerEntitySelectionSheet(api: actions.api, entity: relation == .unit ? "unit" : "delivery-time",
                                         title: String(localized: relation == .unit ? "Unit" : "Delivery time"), multiple: false,
                                         selected: Set([relation == .unit ? draft.unitID : draft.deliveryTimeID].filter { !$0.isEmpty }), sortField: "name") {
                if relation == .unit { draft.unitID = $0.first ?? "" } else { draft.deliveryTimeID = $0.first ?? "" }
            }
        }
    }
    private func number(_ field: ProductInventoryField) -> some View {
        LabeledContent {
            TextField(field.title, text: $draft[field]).labelsHidden().multilineTextAlignment(.trailing)
                .accessibilityIdentifier("product.inventory." + field.rawValue)
                #if os(iOS)
                .keyboardType(field == .stock ? .numbersAndPunctuation : .decimalPad)
                #endif
        } label: { Text(field.title) }
    }
}

private enum ProductInventoryRelation: String, Identifiable { case unit, deliveryTime; var id: String { rawValue } }
