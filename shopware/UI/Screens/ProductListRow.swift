import SwiftUI

struct ProductListRow: View {
    let product: ProductItem
    let currency: String?
    let showPrice: Bool
    let lowStock: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize { ProductThumbnail(url: product.coverURL) }
            VStack(alignment: .leading, spacing: 5) {
                Text(product.name).foregroundStyle(.primary).fontWeight(.medium).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                Text(product.productNumber).font(.callout).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { facts }
                    VStack(alignment: .leading, spacing: 4) { facts }
                }.font(.callout)
                if product.childCount > 0 {
                    Text("\(product.childCount) variants").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 4)
    }
    @ViewBuilder private var facts: some View {
        Text(product.active ? "Active" : "Inactive").foregroundStyle(product.active ? Color.secondary : Color.orange)
        Text("\(product.stock) in stock").foregroundStyle(product.stock <= 0 ? .red : product.stock <= lowStock ? .orange : .secondary)
        if showPrice { ProductMoneyText(amount: product.grossPrice, currency: currency) }
    }
}
