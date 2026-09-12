import SwiftUI
import ShopwareAdminAPI

/// Uses the existing paged entity picker, so filters also work with large catalogs.
struct ReviewFilterSheet: View {
    let listing: ListingState<ReviewItem>
    let api: ShopApi
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FilterDraft()
    @State private var seeded = false
    @State private var picker: ReviewEntityFilter?
    private var validRating: Bool {
        let range = draft.rangeBinding("points").wrappedValue
        return (range.min.map { (0...5).contains($0) } ?? true)
            && (range.max.map { (0...5).contains($0) } ?? true)
            && (range.min == nil || range.max == nil || range.min! <= range.max!)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Approval") {
                    Picker("Approval", selection: draft.boolBinding("status")) {
                        Text("All reviews").tag(String?.none)
                        Text("Pending").tag(String?.some("false"))
                        Text("Approved").tag(String?.some("true"))
                    }
                }
                Section("Filter by") {
                    ForEach(ReviewEntityFilter.allCases) { filter in
                        Button { picker = filter } label: {
                            LabeledContent(filter.label) {
                                let count = draft.optionsBinding(filter.rawValue).wrappedValue.count
                                Text(count == 0 ? String(localized: "Any") : String(localized: "\(count) selected"))
                            }
                        }.accessibilityIdentifier("reviews.filter.\(filter.rawValue)")
                    }
                }
                Section {
                    RangeEditor(value: draft.rangeBinding("points"))
                    if !validRating { Text("Choose a rating range between 0 and 5.").foregroundStyle(.red) }
                } header: { Text("Rating") } footer: { Text("Leave either field empty for no limit.") }
            }.groupedFormStyle()
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { listing.applyFilterValues(draft.values); dismiss() }.disabled(!validRating).accessibilityIdentifier("reviews.filters.apply") }
                ToolbarItem(placement: .automatic) { Button("Reset") { draft.clear() } }
            }
            .onAppear { if !seeded { draft.seed(listing.activeValues); seeded = true } }
            .sheet(item: $picker) { filter in
                CustomerEntitySelectionSheet(api: api, entity: filter.entity, title: filter.label, multiple: true,
                                             selected: draft.optionsBinding(filter.rawValue).wrappedValue, labelProperty: filter == .customer ? "email" : "name", sortField: filter == .customer ? "email" : "name") {
                    draft.optionsBinding(filter.rawValue).wrappedValue = $0
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 530)
        #endif
    }
}
private enum ReviewEntityFilter: String, CaseIterable, Identifiable {
    case salesChannel, language, customer, product
    var id: String { rawValue }
    var entity: String { self == .salesChannel ? "sales-channel" : rawValue }
    var label: String {
        switch self {
        case .salesChannel: String(localized: "Sales channel")
        case .language: String(localized: "Language")
        case .customer: String(localized: "Customer")
        case .product: String(localized: "Product")
        }
    }
}
