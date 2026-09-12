import SwiftUI
import ShopwareAdminAPI

struct ProductFilterSheet: View {
    let listing: ListingState<ProductItem>
    let api: ShopApi
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FilterDraft()
    @State private var seeded = false
    @State private var selecting: ProductFilterRelation?
    private var validation: String? {
        for key in ["stock", "price"] {
            let range = draft.rangeBinding(key).wrappedValue
            if let min = range.min, let max = range.max, min > max { return String(localized: "The minimum must not exceed the maximum.") }
        }
        let dates = draft.dateBinding("releaseDate").wrappedValue
        if let from = dates.from, let to = dates.to, from > to { return String(localized: "The start date must not be after the end date.") }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Availability") {
                    Picker("Status", selection: draft.boolBinding("active")) {
                        Text("Any").tag(String?.none); Text("Active").tag(String?.some("true")); Text("Inactive").tag(String?.some("false"))
                    }
                    Picker("Images", selection: draft.existenceBinding("images")) {
                        Text("Any").tag(Bool?.none); Text("Has images").tag(Bool?.some(true)); Text("No images").tag(Bool?.some(false))
                    }
                }
                Section("Assignments") {
                    ForEach(ProductFilterRelation.allCases) { relation in
                        Button { selecting = relation } label: {
                            LabeledContent { Text("\(draft.optionsBinding(relation.rawValue).wrappedValue.count) selected").foregroundStyle(.secondary) } label: { Text(relation.title) }
                        }.accessibilityIdentifier("products.filter." + relation.rawValue)
                    }
                }
                Section("Product number") { TextField("Product number", text: draft.textBinding("productNumber")).labelsHidden() }
                Section("Stock") { RangeEditor(value: draft.rangeBinding("stock")) }
                Section("Price") { RangeEditor(value: draft.rangeBinding("price")) }
                Section("Release date") { DateRangeEditor(value: draft.dateBinding("releaseDate"), withPresets: false) }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }.groupedFormStyle()
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { listing.applyFilterValues(draft.values); dismiss() }.disabled(validation != nil).accessibilityIdentifier("products.filters.apply") }
                ToolbarItem { Button("Reset") { draft.clear() } }
            }
            .onAppear { if !seeded { draft.seed(listing.activeValues); seeded = true } }
            .sheet(item: $selecting) { relation in
                CustomerEntitySelectionSheet(api: api, entity: relation.entity, title: String(localized: relation.title), multiple: true,
                                             selected: draft.optionsBinding(relation.rawValue).wrappedValue, sortField: "name") { draft.optionsBinding(relation.rawValue).wrappedValue = $0 }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 600).presentationSizing(.fitted)
        #endif
    }
}

private enum ProductFilterRelation: String, Identifiable, CaseIterable {
    case manufacturer, salesChannel, categories, tags
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self { case .manufacturer: "Manufacturer"; case .salesChannel: "Sales channels"; case .categories: "Categories"; case .tags: "Tags" }
    }
    var entity: String {
        switch self { case .manufacturer: "product-manufacturer"; case .salesChannel: "sales-channel"; case .categories: "category"; case .tags: "tag" }
    }
}
