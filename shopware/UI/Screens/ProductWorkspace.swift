import SwiftUI
import ShopwareAdminAPI

struct ProductWorkspace: View {
    let shop: ConnectedShop
    @Bindable var listing: ListingState<ProductItem>
    @Environment(AppViewModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var actions: ProductActions
    @State private var wide = false
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var productID: String?
    @State private var sheet: ProductListSheet?
    @State private var deleting = false
    @State private var sorting = [KeyPathComparator(\ProductItem.name)]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    init(shop: ConnectedShop, api: ShopApi, listing: ListingState<ProductItem>) {
        self.shop = shop; self.listing = listing
        _actions = State(initialValue: ProductActions(api: api))
    }
    private var useTable: Bool {
        #if os(iOS)
        wide && sizeClass == .regular && !typeSize.isAccessibilitySize
        #else
        wide && !typeSize.isAccessibilitySize
        #endif
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if typeSize.isAccessibilitySize { availability.pickerStyle(.menu) }
                    else { availability.pickerStyle(.segmented).labelsHidden() }
                }.frame(maxWidth: 420)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = actions.permissionsError { PromotionNotice(message: error) { Task { await actions.loadPermissions() } } }
            if let error = actions.currencyError { PromotionNotice(message: error) { Task { await actions.loadCurrencies() } } }
            if let error = listing.error, !listing.items.isEmpty { PromotionNotice(message: error) { listing.reload() } }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if listing.loading || actions.busy { ProgressView().controlSize(.small) }
                Text(selection.isEmpty ? String(localized: "\(listing.total) products") : String(localized: "\(selection.count) selected"))
                    .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("products.count")
                Spacer()
                if !selection.isEmpty {
                    Menu("Actions") {
                        if actions.permissions.allows("product:update") {
                            Button("Activate products") { Task { await updateSelection(active: true) } }
                            Button("Deactivate products") { Task { await updateSelection(active: false) } }
                        }
                        if actions.permissions.allows("product:delete") { Button("Delete products…", role: .destructive) { deleting = true } }
                    }.disabled(actions.busy).accessibilityIdentifier("products.selection.actions")
                }
                if listing.items.count < listing.total { Button("Load more") { listing.loadMore() }.disabled(listing.loading).accessibilityIdentifier("products.loadMore") }
            }.padding(.horizontal, 16).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 840 } action: { wide = $0 }
        .searchable(text: $search, prompt: "Search products")
        .task(id: search) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard search != listing.term else { return }
                selection = []; listing.setTerm(search); listing.search()
            } catch { }
        }
        .task { await actions.loadPermissions() }
        .onChange(of: listing.activeValues) { selection = [] }
        .onChange(of: sorting) { applySorting() }
        .onChange(of: productID) { old, new in if old != nil && new == nil { selection = []; listing.reload() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New product", systemImage: "plus") { sheet = .create }.disabled(!actions.canCreate).accessibilityIdentifier("products.create")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Filters", systemImage: listing.activeFilterCount == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") { sheet = .filters }
                    .badge(listing.activeFilterCount).accessibilityIdentifier("products.filters")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if actions.permissions.allows("product:delete") || actions.permissions.allows("product:update") {
                        Button(selecting ? "Done selecting" : "Select products") { selecting.toggle(); selection = [] }
                        Button("Select loaded products") { selection = Set(listing.items.map(\.id)); selecting = true }.accessibilityIdentifier("products.selectAll")
                        Button("Clear selection") { selection = [] }.disabled(selection.isEmpty)
                        Divider()
                    }
                    Menu("Sort products") {
                        Button("Name") { sorting = [KeyPathComparator(\ProductItem.name)] }
                        Button("Product number") { sorting = [KeyPathComparator(\ProductItem.productNumber)] }
                        Button("Newest first") { sorting = [KeyPathComparator(\ProductItem.createdOrder, order: .reverse)] }
                        Button("Lowest stock") { sorting = [KeyPathComparator(\ProductItem.stock)] }
                        Button("Most sold") { sorting = [KeyPathComparator(\ProductItem.sales, order: .reverse)] }
                    }
                    Button("Refresh products", systemImage: "arrow.clockwise") { listing.reload() }.disabled(listing.loading)
                } label: { Label("Product list actions", systemImage: "ellipsis.circle") }
                .disabled(actions.busy).accessibilityIdentifier("products.actions")
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .filters: ProductFilterSheet(listing: listing, api: actions.api)
            case .create: ProductEditorSheet(product: nil, shop: shop, actions: actions) { id in listing.reload(); model.refresh(shop.id); productID = id }
            }
        }
        .navigationDestination(item: $productID) { ProductDetailView(shop: shop, productId: $0) }
        .confirmationDialog("Delete selected products?", isPresented: $deleting, titleVisibility: .visible) {
            Button(selection.count == 1 ? String(localized: "Delete product") : String(localized: "Delete \(selection.count) products"), role: .destructive) { Task { await deleteSelection() } }
        } message: { Text("The products and their variants will be permanently deleted. Media files remain in the media library.") }
        .alert("Couldn't update products", isPresented: Binding(get: { actions.error != nil && sheet == nil }, set: { if !$0 { actions.error = nil } })) {
            Button("OK", role: .cancel) { actions.error = nil }
        } message: { Text(actions.error ?? "") }
    }
    private var availability: some View {
        Picker("Product availability", selection: Binding(get: {
            if case .options(let ids) = listing.activeValues["active"] { return ids.first ?? "all" }; return "all"
        }, set: { selection = []; listing.setFilterValue("active", $0 == "all" ? nil : .options([$0])) })) {
            Text("All products").tag("all"); Text("Active").tag("true"); Text("Inactive").tag("false")
        }.accessibilityIdentifier("products.availability")
    }
    @ViewBuilder private var content: some View {
        if listing.items.isEmpty && listing.loading { ProgressView("Loading products…") }
        else if listing.items.isEmpty, let error = listing.error {
            ContentUnavailableView { Label("Couldn't load products", systemImage: "exclamationmark.triangle") }
            description: { Text(error) } actions: { Button("Retry") { listing.reload() } }
        } else if listing.items.isEmpty {
            ContentUnavailableView { Label(listing.activeFilterCount == 0 && listing.term.isEmpty ? "No products yet" : "No matching products", systemImage: "shippingbox") }
            description: { Text("Manage products, prices, and stock for your shop.") }
            actions: {
                if listing.activeFilterCount > 0 { Button("Clear filters") { listing.applyFilterValues([:]) } }
                else if actions.canCreate { Button("New product…") { sheet = .create } }
            }
        } else if useTable { table }
        else {
            List(listing.items) { item in
                Button {
                    if selecting { if !selection.insert(item.id).inserted { selection.remove(item.id) } }
                    else { productID = item.id }
                } label: {
                    HStack(alignment: .top) {
                        if selecting { Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
                        ProductListRow(product: item, currency: actions.currencyCode, showPrice: shop.productFields.showPrice, lowStock: shop.lowStockThreshold)
                        if !selecting { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
                    }.contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("products.row." + item.id).contextMenu { rowActions(item) }
            }.refreshable { listing.reload(); await listing.fetchTask?.value }
        }
    }
    private var table: some View {
        Table(listing.items, selection: $selection, sortOrder: $sorting) {
            TableColumn("Product", value: \.name) { item in
                Button { productID = item.id } label: {
                    HStack { ProductThumbnail(url: item.coverURL, size: 32); Text(item.name).fontWeight(.medium).lineLimit(2) }
                }.buttonStyle(.plain).accessibilityIdentifier("products.row." + item.id)
            }.width(min: 180, ideal: 250)
            TableColumn("Product number", value: \.productNumber).width(min: 105, ideal: 135)
            TableColumn("Status") { Text($0.active ? "Active" : "Inactive").foregroundStyle($0.active ? Color.secondary : Color.orange) }.width(min: 65, ideal: 75)
            TableColumn("Stock", value: \.stock) { Text($0.stock, format: .number).monospacedDigit() }.width(min: 55, ideal: 65)
            TableColumn("Available") { if let stock = $0.availableStock { Text(stock, format: .number) } else { Text("—") } }.width(min: 60, ideal: 70)
            TableColumn("Price") { if shop.productFields.showPrice { ProductMoneyText(amount: $0.grossPrice, currency: actions.currencyCode) } }.width(min: 80, ideal: 100)
            TableColumn("Manufacturer", value: \.manufacturer) { if shop.productFields.showManufacturer { Text($0.manufacturer).foregroundStyle(.secondary) } }.width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let item = listing.items.first(where: { ids.contains($0.id) }) { rowActions(item) }
        } primaryAction: { ids in if ids.count == 1 { productID = ids.first } }
    }
    @ViewBuilder private func rowActions(_ item: ProductItem) -> some View {
        Button("Open product") { productID = item.id }
        if actions.canEdit {
            Button(item.active ? "Deactivate" : "Activate") {
                Task { if await actions.setActive(ids: [item.id], active: !item.active).contains(item.id) { listing.reload(); model.refresh(shop.id) } }
            }
        }
        if actions.canDelete { Button("Delete product…", role: .destructive) { selection = [item.id]; deleting = true } }
    }
    private func deleteSelection() async {
        let succeeded = await actions.delete(ids: selection)
        selection.subtract(succeeded); if selection.isEmpty { selecting = false }
        listing.removeItem { succeeded.contains($0.id) }
        if !succeeded.isEmpty { listing.reload(); model.refresh(shop.id) }
    }
    private func updateSelection(active: Bool) async {
        let succeeded = await actions.setActive(ids: selection, active: active)
        selection.subtract(succeeded); if selection.isEmpty { selecting = false }
        if !succeeded.isEmpty { listing.reload(); model.refresh(shop.id) }
    }
    private func applySorting() {
        selection = []
        let fields: [PartialKeyPath<ProductItem>: String] = [\ProductItem.name: "name", \ProductItem.productNumber: "productNumber", \ProductItem.stock: "stock", \ProductItem.sales: "sales", \ProductItem.createdOrder: "createdAt", \ProductItem.manufacturer: "manufacturer.name"]
        listing.setSorting(sorting.compactMap { sort in fields[sort.keyPath].map { ListingSort(field: $0, ascending: sort.order != .reverse) } })
    }
}

private enum ProductListSheet: String, Identifiable { case filters, create; var id: String { rawValue } }
