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
                variants = (try? await repo.productVariants(shop, parentId: productId)) ?? []
            } else {
                variants = []
            }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    func saveDetail(name: String, description: String?, active: Bool, stock: Int, newGross: Double?) async {
        guard let detail else { return }
        do {
            try await repo.saveProductDetail(
                shop, detail: detail, name: name, description: description,
                active: active, stock: stock, newGross: newGross
            )
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    func saveVariant(_ variant: ProductVariant, stock: Int, newGross: Double?) async {
        do {
            try await repo.saveVariantEdit(shop, variant: variant, stock: stock, newGross: newGross)
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
                ProductEditSheet(shop: shop, detail: detail) { name, description, active, stock, newGross in
                    Task { await vm?.saveDetail(name: name, description: description, active: active, stock: stock, newGross: newGross) }
                }
            }
        }
        .sheet(item: $editingVariant) { variant in
            VariantEditSheet(shop: shop, variant: variant) { stock, newGross in
                Task { await vm?.saveVariant(variant, stock: stock, newGross: newGross) }
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

            Section("Details") {
                LabeledContent("Gross price", value: shop.fmt(detail.grossPrice ?? 0))
                if let net = detail.netPrice {
                    LabeledContent("Net price", value: shop.fmt(net))
                }
                LabeledContent("Stock", value: "\(detail.stock)")
                LabeledContent("Available", value: "\(detail.availableStock)")
                if let tax = detail.taxRate {
                    LabeledContent("Tax rate", value: "\(String(format: "%.0f", tax)) %")
                }
                if let manufacturer = detail.manufacturer {
                    LabeledContent("Manufacturer", value: manufacturer)
                }
                if let rating = detail.ratingAverage {
                    LabeledContent("Rating") { stars(rating) }
                }
            }

            if !detail.categories.isEmpty {
                Section("Categories") {
                    Text(detail.categories.joined(separator: ", "))
                }
            }

            if !detail.salesChannels.isEmpty {
                Section("Sales channels") {
                    Text(detail.salesChannels.joined(separator: ", "))
                }
            }

            if let description = detail.description {
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
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(shop.fmt(variant.grossPrice ?? 0))
                                        .font(.subheadline.weight(.medium))
                                    StatusBadge(label: "\(variant.stock)", tone: variantTone(variant.stock))
                                }
                            }
                        }
                    }
                }
            }
        }
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

    private func variantTone(_ stock: Int) -> BadgeTone {
        if stock <= 0 { return .error }
        if stock < 10 { return .warning }
        return .done
    }
}

/// Edits a product's base data: name, description, active flag, stock and (when editable) gross price.
private struct ProductEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let detail: ProductDetail
    let onSave: (_ name: String, _ description: String?, _ active: Bool, _ stock: Int, _ newGross: Double?) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var active = false
    @State private var stock = 0
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Toggle("Active in shop", isOn: $active)
                    Stepper("Stock: \(stock)", value: $stock, in: 0 ... 999_999)
                }

                Section("Price") {
                    if detail.priceEditable {
                        TextField("Gross price", text: $priceText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } else {
                        Text("Price not editable (advanced prices)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
            }
            .navigationTitle("Edit product")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newGross = detail.priceEditable
                            ? Double(priceText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 != detail.grossPrice ? $0 : nil }
                            : nil
                        onSave(name, description.isEmpty ? nil : description, active, stock, newGross)
                        dismiss()
                    }
                }
            }
            .task {
                name = detail.name
                description = detail.description ?? ""
                active = detail.active
                stock = detail.stock
                priceText = detail.grossPrice.map { String($0) } ?? ""
            }
        }
    }
}

/// Edits a single variant's stock and (when editable) gross price.
private struct VariantEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let variant: ProductVariant
    let onSave: (_ stock: Int, _ newGross: Double?) -> Void

    @State private var stock = 0
    @State private var priceText = ""

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
                    if variant.priceEditable {
                        TextField("Gross price", text: $priceText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } else {
                        Text("Price not editable (advanced prices)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit variant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newGross = variant.priceEditable
                            ? Double(priceText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 != variant.grossPrice ? $0 : nil }
                            : nil
                        onSave(stock, newGross)
                        dismiss()
                    }
                }
            }
            .task {
                stock = variant.stock
                priceText = variant.grossPrice.map { String($0) } ?? ""
            }
        }
    }
}
