import SwiftUI
import ShopwareAdminAPI

struct ProductDetailWorkspace: View {
    let vm: ProductDetailViewModel
    let product: ProductItem
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section = ProductDetailSection.overview
    @State private var sheet: ProductDetailSheet?
    @State private var deleting = false
    @State private var wide = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if typeSize.isAccessibilitySize || !wide { sections.pickerStyle(.menu) }
                    else { sections.pickerStyle(.segmented).labelsHidden() }
                }.frame(maxWidth: 660, alignment: .leading)
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = vm.error { PromotionNotice(message: error) { Task { await vm.load() } } }
            if let error = vm.actions.permissionsError { PromotionNotice(message: error) { Task { await vm.actions.loadPermissions() } } }
            if let error = vm.actions.currencyError { PromotionNotice(message: error) { Task { await vm.actions.loadCurrencies() } } }
            Group {
                switch section {
                case .overview: ProductOverviewContent(product: product, vm: vm) { sheet = .organization }
                case .prices: ProductPricesContent(product: product, actions: vm.actions, shop: vm.shop) { sheet = .price($0) }
                case .inventory: ProductInventoryContent(product: product, actions: vm.actions) { sheet = .inventory }
                case .media: ProductMediaContent(product: product, actions: vm.actions, onSave: saved)
                case .variants: ProductVariantsContent(vm: vm)
                }
            }.frame(maxWidth: section == .media || section == .variants ? .infinity : 960)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 630 } action: { wide = $0 }
        .overlay { if vm.loading { ProgressView("Loading product…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit product", systemImage: "pencil") { sheet = .general }
                    .disabled(!vm.actions.canEdit || vm.loading).accessibilityIdentifier("product.edit")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if vm.actions.permissions.allows("product:update") {
                        Button(product.active ? "Deactivate" : "Activate") {
                            Task { if await vm.actions.setActive(ids: [product.id], active: !product.active).contains(product.id) { saved() } }
                        }.accessibilityIdentifier("product.toggleActive")
                    }
                    Button("Refresh product", systemImage: "arrow.clockwise") { Task { await vm.load(); vm.variants.reload() } }
                    if vm.actions.permissions.allows("product:delete") {
                        Button("Delete product…", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("product.delete")
                    }
                } label: { Label("Product actions", systemImage: "ellipsis.circle") }
                .disabled(vm.actions.busy || vm.loading).accessibilityIdentifier("product.actions")
            }
        }
        .sheet(item: $sheet, onDismiss: { vm.actions.error = nil }) { destination in
            switch destination {
            case .general: ProductEditorSheet(product: product, shop: vm.shop, actions: vm.actions) { _ in saved() }
            case .inventory: ProductInventoryEditorSheet(product: product, actions: vm.actions, onSave: saved)
            case .price(let currency): ProductPriceEditorSheet(product: product, currency: currency, actions: vm.actions, onSave: saved)
            case .organization: ProductOrganizationEditorSheet(product: product, actions: vm.actions, onSave: saved)
            }
        }
        .confirmationDialog("Delete product?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete product", role: .destructive) {
                Task { if await vm.actions.delete(ids: [product.id]).contains(product.id) { model.refresh(vm.shop.id); dismiss() } }
            }
        } message: { Text("The product and its variants will be permanently deleted. Media files remain in the media library.") }
        .alert("Couldn't update product", isPresented: Binding(get: { vm.actions.error != nil && sheet == nil && section != .media }, set: { if !$0 { vm.actions.error = nil } })) {
            Button("OK", role: .cancel) { vm.actions.error = nil }
        } message: { Text(vm.actions.error ?? "") }
    }
    private var sections: some View {
        Picker("Product section", selection: $section) {
            ForEach(ProductDetailSection.allCases) { Text($0.title).tag($0).accessibilityIdentifier("product.tab." + $0.rawValue) }
        }.accessibilityIdentifier("product.section")
    }
    private func saved() { model.refresh(vm.shop.id); Task { await vm.load() } }
}

private enum ProductDetailSheet: Identifiable {
    case general, inventory, organization, price(ProductCurrency)
    var id: String {
        switch self { case .general: "general"; case .inventory: "inventory"; case .organization: "organization"; case .price(let currency): "price-" + currency.id }
    }
}
