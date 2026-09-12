import SwiftUI

struct ProductVariantsContent: View {
    let vm: ProductDetailViewModel
    @State private var search = ""
    @State private var wide = false
    @State private var selectedID: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var listing: ListingState<ProductItem> { vm.variants }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search variants", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("product.variants.search")
                Button("Refresh variants", systemImage: "arrow.clockwise") { listing.reload() }.labelStyle(.iconOnly).disabled(listing.loading)
            }.padding().fixedSize(horizontal: false, vertical: true)
            if let error = listing.error { PromotionNotice(message: error) { listing.reload() } }
            Group {
                if listing.items.isEmpty && listing.loading { ProgressView("Loading variants…") }
                else if listing.items.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No variants" : "No matching variants", systemImage: "square.stack.3d.up",
                                           description: Text("Variants represent combinations such as size and color."))
                } else if wide && !typeSize.isAccessibilitySize {
                    Table(listing.items, selection: $selectedID) {
                        TableColumn("Variant") { item in
                            Button { selectedID = item.id } label: { Text(item.optionLabel.isEmpty ? item.name : item.optionLabel) }.buttonStyle(.plain)
                                .accessibilityIdentifier("product.variant." + item.id)
                        }.width(min: 170, ideal: 240)
                        TableColumn("Product number") { Text($0.productNumber) }
                        TableColumn("Status") { Text($0.active ? "Active" : "Inactive") }.width(80)
                        TableColumn("Stock") { Text($0.stock, format: .number) }.width(70)
                        TableColumn("Price") { if vm.shop.productFields.showPrice { ProductMoneyText(amount: $0.grossPrice, currency: vm.actions.currencyCode) } }.width(100)
                    }
                } else {
                    List(listing.items) { item in
                        NavigationLink { ProductDetailView(shop: vm.shop, productId: item.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.optionLabel.isEmpty ? item.name : item.optionLabel).fontWeight(.medium)
                                Text(item.productNumber).foregroundStyle(.secondary)
                                HStack { Text("\(item.stock) in stock"); if vm.shop.productFields.showPrice { ProductMoneyText(amount: item.grossPrice, currency: vm.actions.currencyCode) } }.font(.callout)
                            }
                        }.accessibilityIdentifier("product.variant." + item.id)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("\(listing.total) variants").foregroundStyle(.secondary)
                Spacer()
                if listing.items.count < listing.total { Button("Load more") { listing.loadMore() }.disabled(listing.loading).accessibilityIdentifier("product.variants.loadMore") }
            }.padding().fixedSize(horizontal: false, vertical: true)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 740 } action: { wide = $0 }
        .task { if listing.items.isEmpty { listing.reload() } }
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(300)); guard search != listing.term else { return }; listing.setTerm(search); listing.search() } catch { }
        }
        .navigationDestination(item: $selectedID) { ProductDetailView(shop: vm.shop, productId: $0) }
    }
}
