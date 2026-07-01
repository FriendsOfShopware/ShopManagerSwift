import SwiftUI
import ShopwareAdminAPI

@MainActor
@Observable
final class ProductsViewModel: ListingViewModel<ProductRow> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<ProductRow> {
        // Port of the Android productFilters config.
        let filters: [ListingFilter] = [
            .bool(key: "active", label: "Active", field: "active",
                  trueLabel: "Active", falseLabel: "Inactive"),
            .numberRange(key: "stock", label: "Stock", field: "stock"),
            .numberRange(key: "price", label: "Price", field: "price"),
            .options(key: "manufacturer", label: "Manufacturer", field: "manufacturer.id",
                     loadOptions: { api in
                         try await api.repository("product-manufacturer").search(
                             Criteria()
                                 .setLimit(100)
                                 .addSorting("name")
                                 .addIncludes("product_manufacturer", ["id", "name", "translated"])
                         ).data.compactMap { m in
                             m.id.map { FilterOption(id: $0, label: m.translated("name") ?? "—") }
                         }
                     }),
            salesChannelFilter(label: "Sales channel", field: "visibilities.salesChannelId"),
            .existence(key: "images", label: "Images", field: "media.id",
                       hasLabel: "Has images", hasNotLabel: "No images"),
            .text(key: "productNumber", label: "Product number", field: "productNumber", mode: .contains),
            .dateRange(key: "releaseDate", label: "Release date", field: "releaseDate"),
        ]

        return ListingState(
            filters: filters,
            source: { try await api.repository("product").search($0) },
            baseCriteria: { productListCriteria() },
            mapper: { parseProduct($0, shop.baseUrl) }
        )
    }
}

/// Products listing. Rows push a rich detail view; quick chips toggle the active/inactive filter.
struct ProductsView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    @State private var vm: ProductsViewModel?

    #if os(macOS)
    @State private var navProductId: String?
    #endif

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                listingContent(listing)
                    .navigationDestination(for: String.self) { productId in
                        ProductDetailView(shop: shop, productId: productId)
                    }
            } else {
                ProgressView()
            }
        }
        #if os(macOS)
        .navigationDestination(item: $navProductId) { id in
            ProductDetailView(shop: shop, productId: id)
        }
        #endif
        .navigationTitle("Products")
        .onAppear {
            if vm == nil { vm = ProductsViewModel(repo: model.repo) }
            vm?.start(shop)
        }
        .onChange(of: shop.id) { vm?.start(shop) }
    }

    @ViewBuilder
    private func listingContent(_ listing: ListingState<ProductRow>) -> some View {
        #if os(macOS)
        MacListingTable(
            state: listing,
            api: vm?.api,
            searchPrompt: "Search products",
            onActivate: { navProductId = $0.id },
            columns: {
                TableColumn("Product") { product in
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: product.coverUrl ?? "")) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ZStack {
                                Rectangle().fill(.quaternary)
                                Image(systemName: "shippingbox").foregroundStyle(.secondary).font(.caption2)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text(product.name).lineLimit(1)
                    }
                }
                TableColumn("Number") { Text($0.productNumber).foregroundStyle(.secondary) }
                    .width(min: 90, ideal: 120)
                TableColumn("Manufacturer") { Text($0.manufacturer ?? "—").foregroundStyle(.secondary) }
                    .width(min: 90, ideal: 140)
                TableColumn("Stock") { product in
                    Text("\(product.stock)")
                        .monospacedDigit()
                        .foregroundStyle(product.stock <= 0 ? .red : product.stock < 10 ? .orange : .secondary)
                }
                .width(min: 50, ideal: 60)
                TableColumn("Price") { product in
                    Text(shop.fmt(product.grossPrice ?? 0)).monospacedDigit().fontWeight(.medium)
                }
                .width(min: 70, ideal: 90)
            },
            rowMenu: { product in
                Button("Open") { navProductId = product.id }
            }
        )
        #else
        ListingScaffold(
            state: listing,
            api: vm?.api,
            searchPrompt: "Search products",
            quickChips: chips(for: listing)
        ) { product in
            NavigationLink(value: product.id) {
                ProductRowView(shop: shop, product: product)
            }
        }
        #endif
    }

    private func chips(for listing: ListingState<ProductRow>) -> [QuickChip] {
        let quick: [(LocalizedStringKey, FilterValue)] = [
            ("Active", .options(["true"])),
            ("Inactive", .options(["false"])),
        ]
        return quick.map { label, value in
            let isOn = listing.activeValues["active"] == value
            return QuickChip(label: label, isOn: isOn) {
                listing.setFilterValue("active", isOn ? nil : value)
            }
        }
    }
}

/// A single product row: cover thumbnail, name, number · manufacturer, price, and a stock badge.
private struct ProductRowView: View {
    let shop: ConnectedShop
    let product: ProductRow

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: product.coverUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "shippingbox").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).lineLimit(1)
                HStack(spacing: 4) {
                    Text(product.productNumber)
                    if let manufacturer = product.manufacturer {
                        Text("· \(manufacturer)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(shop.fmt(product.grossPrice ?? 0))
                    .font(.body.weight(.medium))
                Text("\(product.stock) in stock")
                    .font(.caption)
                    .foregroundStyle(stockTone)
            }
        }
    }

    private var stockTone: Color {
        if product.stock <= 0 { return .red }
        if product.stock < 10 { return .orange }
        return .secondary
    }
}
