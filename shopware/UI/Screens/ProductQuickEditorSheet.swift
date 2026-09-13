import ShopwareDomain
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProductQuickEditorSheet: View {
    let product: ProductItem
    let shop: ConnectedShop
    let actions: ProductActions
    let onSave: () -> Void
    @Environment(\.locale) private var locale
    @State private var stock: String
    @State private var active: Bool
    @State private var price: ProductPriceDraft
    @State private var photo: PhotosPickerItem?
    @State private var uploaded = false
    #if os(iOS)
    @State private var camera = false
    #endif
    init(product: ProductItem, shop: ConnectedShop, actions: ProductActions, onSave: @escaping () -> Void) {
        self.product = product; self.shop = shop; self.actions = actions; self.onSave = onSave
        _stock = State(initialValue: String(product.stock)); _active = State(initialValue: product.active)
        _price = State(initialValue: ProductPriceDraft(price: product.defaultPrice, locale: Locale.current))
    }
    private var canEditPrice: Bool { shop.productFields.showPrice && shop.productFields.editPrice && actions.currencyCode != nil }
    private var changed: Bool { stock != String(product.stock) || active != product.active || (canEditPrice && price != ProductPriceDraft(price: product.defaultPrice, locale: locale)) }
    var body: some View {
        EntityEditorSheet(title: "Quick edit", identifier: "product", busy: actions.busy, changed: changed,
                          canSave: actions.canEdit && ProductNumberInput.integer(stock) != nil && (!canEditPrice || price.validationError(locale: locale) == nil), error: actions.error, idealHeight: 540) {
            let saved = await actions.saveQuick(product, stock: stock, active: active, price: canEditPrice ? price : nil, locale: locale)
            if saved { onSave() }; return saved
        } content: {
            Section { Text(product.name).font(.headline); Text(product.productNumber).foregroundStyle(.secondary) }
            Section {
                Toggle("Active in shop", isOn: $active)
                LabeledContent("Stock") { TextField("Stock", text: $stock).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("product.quick.stock") }
                if ProductNumberInput.integer(stock) == nil { Text("Enter a valid stock quantity.").foregroundStyle(.red) }
            }
            if canEditPrice { Section("Price") { ProductPriceFields(draft: $price, taxRate: product.taxRate, currency: actions.currencyCode ?? "—") } }
            else if shop.productFields.showPrice {
                Section("Price") {
                    LabeledContent("Gross price") { ProductMoneyText(amount: product.grossPrice, currency: actions.currencyCode) }
                    LabeledContent("Net price") { ProductMoneyText(amount: product.netPrice, currency: actions.currencyCode) }
                }
            }
            if let error = actions.currencyError { Section { PromotionNotice(message: error) { Task { await actions.loadCurrencies() } } } }
            if !product.isVariant {
                Section {
                    PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) { Label("Choose cover photo", systemImage: "photo") }
                        .disabled(!actions.canUpload || actions.pendingMediaID != nil)
                    #if os(iOS)
                    Button("Take photo", systemImage: "camera") { camera = true }.disabled(!actions.canUpload || actions.pendingMediaID != nil)
                    #endif
                    if uploaded { Label("Cover photo updated", systemImage: "checkmark.circle").foregroundStyle(.green) }
                    if actions.pendingMediaID != nil { Button("Retry adding the uploaded photo") { Task { if await actions.retryMediaAttachment(product) { uploaded = true; onSave() } } } }
                } footer: { Text("Cover photos are saved immediately.") }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
                    await upload(data, type: item.supportedContentTypes.first ?? .jpeg)
                } catch { actions.error = error.localizedDescription }
                photo = nil
            }
        }
        #if os(iOS)
        .sheet(isPresented: $camera) { CameraPicker { data in Task { await upload(data, type: .jpeg) } } }
        #endif
    }
    private func upload(_ data: Data, type: UTType) async {
        if await actions.uploadMedia(product, data: data, fileExtension: type.preferredFilenameExtension ?? "jpg", fileName: nil,
                                     mimeType: type.preferredMIMEType ?? "image/jpeg", makeCover: true) { uploaded = true; onSave() }
    }
}
