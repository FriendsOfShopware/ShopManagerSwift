import SwiftUI
import ShopwareAdminAPI

@MainActor
@Observable
final class ProductDetailViewModel {
    private let repo: AppRepository
    let shop: ConnectedShop
    let productId: String

    private(set) var detail: ProductDetail?
    private(set) var variants: [ProductVariant] = []
    private(set) var loading = false
    private(set) var error: String?

    init(repo: AppRepository, shop: ConnectedShop, productId: String) {
        self.repo = repo
        self.shop = shop
        self.productId = productId
    }

    func load() async {
        loading = true
        error = nil
        do {
            let loaded = try await repo.productDetail(shop, productId: productId)
            detail = loaded
            if let loaded, loaded.childCount > 0 {
                variants = (try? await repo.productVariants(shop, parentId: productId, parentTaxRate: loaded.taxRate)) ?? []
            } else {
                variants = []
            }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    func saveDetail(name: String, active: Bool, stock: Int, ean: String?, manufacturerNumber: String?, price: PriceEdit?) async {
        guard let detail else { return }
        do {
            try await repo.saveProductDetail(
                shop, detail: detail, name: name, active: active, stock: stock,
                ean: ean, manufacturerNumber: manufacturerNumber, price: price
            )
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    func saveVariant(_ variant: ProductVariant, stock: Int, price: PriceEdit?) async {
        do {
            try await repo.saveVariantEdit(shop, variant: variant, stock: stock, price: price)
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }
}

/// Rich product detail: cover, key facts, gallery, description, and (for configurable products)
/// an editable list of variants. The pencil toolbar opens the base-data edit sheet.
struct ProductDetailView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let productId: String

    @State private var vm: ProductDetailViewModel?
    @State private var showingEdit = false
    @State private var editingVariant: ProductVariant?

    var body: some View {
        Group {
            if let vm, let detail = vm.detail {
                content(detail, vm: vm)
            } else if let vm, let error = vm.error {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Product")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if vm?.detail != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEdit = true } label: { Image(systemName: "pencil") }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let detail = vm?.detail {
                ProductEditSheet(shop: shop, detail: detail) { name, active, stock, ean, mpn, price in
                    Task { await vm?.saveDetail(name: name, active: active, stock: stock, ean: ean, manufacturerNumber: mpn, price: price) }
                }
            }
        }
        .sheet(item: $editingVariant) { variant in
            VariantEditSheet(shop: shop, variant: variant) { stock, price in
                Task { await vm?.saveVariant(variant, stock: stock, price: price) }
            }
        }
        .task {
            if vm == nil { vm = ProductDetailViewModel(repo: model.repo, shop: shop, productId: productId) }
            await vm?.load()
        }
    }

    private func content(_ detail: ProductDetail, vm: ProductDetailViewModel) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    AsyncImage(url: URL(string: detail.coverUrl ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "shippingbox")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(detail.name).font(.title2.bold())
                    HStack(spacing: 8) {
                        Text(detail.productNumber).font(.subheadline).foregroundStyle(.secondary)
                        StatusBadge(label: detail.active ? "Active" : "Inactive", tone: detail.active ? .done : .error)
                    }
                }
            }

            if !detail.galleryUrls.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detail.galleryUrls, id: \.self) { url in
                                AsyncImage(url: URL(string: url)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "photo").foregroundStyle(.secondary)
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            let cfg = shop.productFields

            Section("Details") {
                if cfg.showPrice {
                    LabeledContent("Gross price", value: shop.fmt(detail.grossPrice ?? 0))
                    if let net = detail.netPrice {
                        LabeledContent("Net price", value: shop.fmt(net))
                    }
                }
                LabeledContent("Stock", value: "\(detail.stock)")
                LabeledContent("Available", value: "\(detail.availableStock)")
                if let tax = detail.taxRate, cfg.showPrice {
                    LabeledContent("Tax rate", value: "\(String(format: "%.0f", tax)) %")
                }
                if let manufacturer = detail.manufacturer, cfg.showManufacturer {
                    LabeledContent("Manufacturer", value: manufacturer)
                }
                if let rating = detail.ratingAverage {
                    LabeledContent("Rating") { stars(rating) }
                }
            }

            let showEan = detail.ean != nil && cfg.showEan
            let showMpn = detail.manufacturerNumber != nil && cfg.showManufacturerNumber
            if showEan || showMpn {
                Section("Identifiers") {
                    if let ean = detail.ean, cfg.showEan {
                        LabeledContent("EAN", value: ean)
                    }
                    if let mpn = detail.manufacturerNumber, cfg.showManufacturerNumber {
                        LabeledContent("Manufacturer no.", value: mpn)
                    }
                }
            }

            if !detail.categories.isEmpty, cfg.showCategories {
                Section("Categories") {
                    Text(detail.categories.joined(separator: ", "))
                }
            }

            if !detail.salesChannels.isEmpty, cfg.showSalesChannels {
                Section("Sales channels") {
                    Text(detail.salesChannels.joined(separator: ", "))
                }
            }

            if let description = detail.description, cfg.showDescription {
                Section("Description") {
                    Text(description)
                }
            }

            if !vm.variants.isEmpty {
                Section("Variants") {
                    ForEach(vm.variants) { variant in
                        Button {
                            editingVariant = variant
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(variant.optionLabels.joined(separator: " · "))
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(variant.productNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(shop.fmt(variant.grossPrice ?? 0))
                                        .font(.body.weight(.medium))
                                    Text("\(variant.stock) in stock")
                                        .font(.caption)
                                        .foregroundStyle(variantTone(variant.stock))
                                }
                            }
                        }
                    }
                }
            }
        }
        .groupedListStyle()
    }

    private func stars(_ rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 5, id: \.self) { i in
                Image(systemName: Double(i) < rating.rounded() ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func variantTone(_ stock: Int) -> Color {
        if stock <= 0 { return .red }
        if stock < 10 { return .orange }
        return .secondary
    }
}

/// Edits a product's base data: name, active flag, stock, EAN/MPN identifiers, and (when editable)
/// the linked gross/net price. Description is not editable (rich HTML).
private struct ProductEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let detail: ProductDetail
    let onSave: (_ name: String, _ active: Bool, _ stock: Int, _ ean: String?, _ mpn: String?, _ price: PriceEdit?) -> Void

    @State private var name = ""
    @State private var active = false
    @State private var stock = 0
    @State private var ean = ""
    @State private var mpn = ""
    @State private var priceModel: PriceEditModel

    init(shop: ConnectedShop, detail: ProductDetail,
         onSave: @escaping (String, Bool, Int, String?, String?, PriceEdit?) -> Void) {
        self.shop = shop
        self.detail = detail
        self.onSave = onSave
        _priceModel = State(initialValue: PriceEditModel(
            gross: detail.grossPrice, net: detail.netPrice, linked: detail.priceLinked, taxRate: detail.taxRate
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Toggle("Active in shop", isOn: $active)
                    Stepper("Stock: \(stock)", value: $stock, in: 0 ... 999_999)
                }

                if shop.productFields.showPrice && shop.productFields.editPrice {
                    Section("Price") {
                        PriceEditor(shop: shop, editable: detail.priceEditable, model: priceModel)
                    }
                }

                let canEditEan = shop.productFields.showEan && shop.productFields.editEan
                let canEditMpn = shop.productFields.showManufacturerNumber && shop.productFields.editManufacturerNumber
                if canEditEan || canEditMpn {
                    Section("Identifiers") {
                        if canEditEan { TextField("EAN", text: $ean) }
                        if canEditMpn { TextField("Manufacturer no.", text: $mpn) }
                    }
                }
            }
            .groupedFormStyle()
            .navigationTitle("Edit product")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, active, stock,
                               ean.isEmpty ? nil : ean, mpn.isEmpty ? nil : mpn,
                               priceModel.edit(editable: detail.priceEditable))
                        dismiss()
                    }
                }
            }
            .task {
                name = detail.name
                active = detail.active
                stock = detail.stock
                ean = detail.ean ?? ""
                mpn = detail.manufacturerNumber ?? ""
            }
        }
    }
}

/// Edits a single variant's stock and (when editable) linked gross/net price.
private struct VariantEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let variant: ProductVariant
    let onSave: (_ stock: Int, _ price: PriceEdit?) -> Void

    @State private var stock = 0
    @State private var priceModel: PriceEditModel

    init(shop: ConnectedShop, variant: ProductVariant, onSave: @escaping (Int, PriceEdit?) -> Void) {
        self.shop = shop
        self.variant = variant
        self.onSave = onSave
        _priceModel = State(initialValue: PriceEditModel(
            gross: variant.grossPrice, net: variant.netPrice, linked: variant.priceLinked, taxRate: variant.taxRate
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(variant.optionLabels.joined(separator: " · ")).font(.headline)
                    Text(variant.productNumber).font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Stepper("Stock: \(stock)", value: $stock, in: 0 ... 999_999)
                }

                Section("Price") {
                    PriceEditor(shop: shop, editable: variant.priceEditable, model: priceModel)
                }
            }
            .groupedFormStyle()
            .navigationTitle("Edit variant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(stock, priceModel.edit(editable: variant.priceEditable))
                        dismiss()
                    }
                }
            }
            .task { stock = variant.stock }
        }
    }
}
