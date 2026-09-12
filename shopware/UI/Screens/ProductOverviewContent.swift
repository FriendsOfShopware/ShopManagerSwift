import SwiftUI
import ShopwareAdminAPI

struct ProductOverviewContent: View {
    let product: ProductItem
    let vm: ProductDetailViewModel
    let editOrganization: () -> Void
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ProductThumbnail(url: product.coverURL, size: 76)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(product.name).font(.title2.bold()).textSelection(.enabled).accessibilityIdentifier("product.name")
                        Text(product.productNumber).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(product.active ? "Active" : "Inactive").foregroundStyle(product.active ? Color.green : Color.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 6)
                if let parentID = product.parentID {
                    NavigationLink { ProductDetailView(shop: vm.shop, productId: parentID) } label: { Label("View parent product", systemImage: "arrow.turn.up.left") }
                    Text("Fields you don't change continue to inherit from the parent product.").foregroundStyle(.secondary)
                }
            }
            Section("Product information") {
                if vm.shop.productFields.showManufacturer { LabeledContent("Manufacturer", value: product.manufacturer.isEmpty ? "—" : product.manufacturer) }
                if vm.shop.productFields.showEan { LabeledContent("EAN", value: product.entity.string("ean") ?? "—") }
                if vm.shop.productFields.showManufacturerNumber { LabeledContent("Manufacturer no.", value: product.entity.string("manufacturerNumber") ?? "—") }
                LabeledContent("Sales") { Text(product.sales, format: .number) }
                if product.childCount > 0 { LabeledContent("Variants") { Text(product.childCount, format: .number) } }
                if let rating = product.entity.double("ratingAverage") { LabeledContent("Average rating") { Text(rating, format: .number.precision(.fractionLength(1))) } }
            }
            if vm.shop.productFields.showDescription {
                Section("Description") {
                    if product.description.isEmpty { Text("No description").foregroundStyle(.secondary) }
                    else { ProductDescriptionText(html: product.description) }
                }
            }
            Section {
                Button("Edit assignments…", systemImage: "pencil", action: editOrganization)
                    .disabled(!vm.actions.canEditOrganization || product.isVariant).accessibilityIdentifier("product.organization.edit")
                if product.isVariant { Text("Manage inherited assignments on the parent product.").foregroundStyle(.secondary) }
            }
            if vm.shop.productFields.showCategories {
                Section("Categories") { references("categories", empty: "No categories assigned") }
            }
            if vm.shop.productFields.showSalesChannels {
                Section("Sales channels") {
                    if product.visibilities.isEmpty { Text("No sales channels assigned").foregroundStyle(.secondary) }
                    ForEach(product.visibilities) { visibility in LabeledContent { Text(visibility.label) } label: { Text(visibility.name) } }
                }
            }
            Section("Properties") {
                if product.references("properties").isEmpty { Text("No properties assigned").foregroundStyle(.secondary) }
                ForEach(product.references("properties")) { value in
                    if let group = value.group { LabeledContent(group, value: value.name) } else { Text(value.name) }
                }
            }
            Section("Tags") { references("tags", empty: "No tags assigned") }
            Section("Search engine listing") {
                LabeledContent("Meta title", value: product.entity.translated("metaTitle") ?? "—")
                LabeledContent("Meta description", value: product.entity.translated("metaDescription") ?? "—")
                LabeledContent("Keywords", value: product.entity.translated("keywords") ?? "—")
            }
            if let error = vm.fieldsError { Section { PromotionNotice(message: error) { Task { await vm.loadFields() } } } }
            ForEach(vm.fields) { set in
                Section(set.label) { ForEach(set.fields) { CustomerCustomFieldSummaryRow(field: $0, value: product.customFields[$0.name], api: vm.actions.api) } }
            }
        }.groupedFormStyle().accessibilityIdentifier("product.overview")
    }
    @ViewBuilder private func references(_ key: String, empty: LocalizedStringResource) -> some View {
        if product.references(key).isEmpty { Text(empty).foregroundStyle(.secondary) }
        ForEach(product.references(key)) { Text($0.name) }
    }
}
