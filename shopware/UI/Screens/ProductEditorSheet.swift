import ShopwareDomain
import SwiftUI
import ShopwareAdminAPI

struct ProductEditorSheet: View {
    private enum Field: String, Hashable { case name, number, ean, manufacturerNumber, stock, metaTitle, keywords }
    let product: ProductItem?
    let shop: ConnectedShop
    let actions: ProductActions
    let onSave: (String) -> Void
    @Environment(\.locale) private var locale
    #if os(iOS)
    @FocusState private var focusedField: Field?
    #endif
    @State private var draft: ProductGeneralDraft
    @State private var original: ProductGeneralDraft
    @State private var id: String
    @State private var price: ProductPriceDraft
    @State private var stock = "0"
    @State private var taxID = ""
    @State private var taxes: [SwEntity] = []
    @State private var fields: [CustomerCustomFieldSet] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var selectingManufacturer = false
    init(product: ProductItem?, shop: ConnectedShop, actions: ProductActions, onSave: @escaping (String) -> Void) {
        self.product = product; self.shop = shop; self.actions = actions; self.onSave = onSave
        let draft = ProductGeneralDraft(product)
        _draft = State(initialValue: draft); _original = State(initialValue: draft)
        _id = State(initialValue: product?.id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        _price = State(initialValue: ProductPriceDraft(price: nil, locale: Locale.current))
    }
    private var changed: Bool { draft != original || (product == nil && (!taxID.isEmpty || !price.gross.isEmpty || stock != "0")) }
    private var validation: String? {
        if let error = draft.validationError(fields: fields) { return error }
        if product == nil {
            if taxID.isEmpty { return String(localized: "Select a tax rate.") }
            if ProductNumberInput.integer(stock) == nil { return String(localized: "Enter a valid stock quantity.") }
            return price.validationError(locale: locale)
        }
        return nil
    }
    var body: some View {
        EntityEditorSheet(title: product == nil ? "New product" : "Edit product", identifier: "product", busy: actions.busy,
                          changed: changed, canSave: loaded && changed && validation == nil && (product == nil ? actions.canCreate && actions.currencyCode != nil : actions.canEdit), error: actions.error,
                          saveTitle: product == nil ? "Create" : "Save") {
            let saved: Bool
            if let product { saved = await actions.saveGeneral(product, draft: draft, fields: fields) }
            else { saved = await actions.create(id: id, draft: draft, fields: fields, taxID: taxID, price: price, stock: stock, locale: locale) }
            if saved { onSave(id) }; return saved
        } content: {
            if let loadError { Section { Text(loadError).foregroundStyle(.red); Button("Retry") { Task { await load() } } } }
            if !loaded && loadError == nil { ProgressView("Loading fields…") }
            Section("Product information") {
                field("Name", text: $draft.name, id: .name)
                field("Product number", text: $draft.productNumber, id: .number)
                Toggle("Active in shop", isOn: $draft.active).accessibilityIdentifier("product.edit.active")
                if shop.productFields.showEan && shop.productFields.editEan { field("EAN", text: $draft.ean, id: .ean) }
                if shop.productFields.showManufacturerNumber && shop.productFields.editManufacturerNumber { field("Manufacturer no.", text: $draft.manufacturerNumber, id: .manufacturerNumber) }
                if shop.productFields.showManufacturer {
                    Button { selectingManufacturer = true } label: {
                        LabeledContent("Manufacturer", value: draft.manufacturerID.isEmpty ? String(localized: "None") : String(localized: "1 selected"))
                    }.disabled(!actions.permissions.allows("product_manufacturer:read"))
                }
            }
            if product == nil {
                Section("Price and stock") {
                    Picker("Tax rate", selection: $taxID) {
                        Text("Select a tax rate").tag("")
                        ForEach(taxes, id: \.id) { Text(customerEntityLabel($0)).tag($0.id ?? "") }
                    }.accessibilityIdentifier("product.edit.tax")
                    ProductPriceFields(draft: $price, taxRate: taxes.first { $0.id == taxID }?.double("taxRate"), currency: actions.currencyCode ?? "—")
                    field("Stock", text: $stock, id: .stock)
                }
            }
            if shop.productFields.showDescription {
                Section("Description") { CustomerRichTextField(label: String(localized: "Description"), value: $draft.description).accessibilityIdentifier("product.edit.description") }
            }
            Section("Search engine listing") {
                field("Meta title", text: $draft.metaTitle, id: .metaTitle)
                TextField("Meta description", text: $draft.metaDescription, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("product.edit.metaDescription")
                field("Keywords", text: $draft.keywords, id: .keywords)
            }
            CustomerCustomFieldsForm(sets: fields, api: actions.api, values: $draft.customFields)
            if let validation { Section { Text(validation).foregroundStyle(.red).accessibilityIdentifier("product.validationError") } }
        }
        .task { actions.error = nil; await load() }
        .onChange(of: taxID) { _, id in
            price.updateGross(price.gross, taxRate: taxes.first { $0.id == id }?.double("taxRate"), locale: locale)
        }
        .sheet(isPresented: $selectingManufacturer) {
            CustomerEntitySelectionSheet(api: actions.api, entity: "product-manufacturer", title: String(localized: "Manufacturer"), multiple: false,
                                         selected: draft.manufacturerID.isEmpty ? [] : [draft.manufacturerID], sortField: "name") { draft.manufacturerID = $0.first ?? "" }
        }
    }
    private func field(_ title: LocalizedStringResource, text: Binding<String>, id: Field) -> some View {
        LabeledContent {
            TextField(title, text: text)
                .labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("product.edit." + id.rawValue)
                #if os(iOS)
                .focused($focusedField, equals: id)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                #endif
        } label: { Text(title) }
    }
    private func load() async {
        loadError = nil
        do {
            if product == nil { taxes = try await actions.api.repository("tax").search(Criteria().setLimit(100).addSorting("taxRate", "DESC")).data }
            if actions.permissions.allows("custom_field_set:read") { fields = try await actions.api.customerCustomFieldSets(entity: "product", locale: shop.localeCode ?? locale.identifier) }
            loaded = true
        } catch { loadError = error.localizedDescription; loaded = false }
    }
}
