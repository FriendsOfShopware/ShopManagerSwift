import SwiftUI
import ShopwareAdminAPI

struct PromotionFilterSheet: View {
    let listing: ListingState<PromotionItem>
    let api: ShopApi
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FilterDraft()
    @State private var seeded = false
    @State private var channels = false
    private var validDates: Bool {
        ["validFrom", "validUntil"].allSatisfy { key in
            let range = draft.dateBinding(key).wrappedValue
            return range.from == nil || range.to == nil || range.from! <= range.to!
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Availability") {
                    Picker("Enabled", selection: draft.boolBinding("active")) {
                        Text("Any").tag(String?.none); Text("Enabled").tag(String?.some("true")); Text("Disabled").tag(String?.some("false"))
                    }
                    Button { channels = true } label: {
                        LabeledContent("Sales channels", value: draft.optionsBinding("salesChannel").wrappedValue.isEmpty ? String(localized: "Any") : String(localized: "\(draft.optionsBinding("salesChannel").wrappedValue.count) selected"))
                    }.accessibilityIdentifier("promotions.filter.channels")
                }
                Section("Promotion codes") {
                    Picker("Requires a code", selection: draft.boolBinding("useCodes")) {
                        Text("Any").tag(String?.none); Text("Yes").tag(String?.some("true")); Text("No").tag(String?.some("false"))
                    }
                    Picker("Individual codes", selection: draft.boolBinding("individual")) {
                        Text("Any").tag(String?.none); Text("Yes").tag(String?.some("true")); Text("No").tag(String?.some("false"))
                    }
                }
                Section("Promotion starts") { DateRangeEditor(value: draft.dateBinding("validFrom"), withPresets: false) }
                Section("Promotion ends") { DateRangeEditor(value: draft.dateBinding("validUntil"), withPresets: false) }
                if !validDates { Text("The end must be after the start.").foregroundStyle(.red) }
            }.groupedFormStyle()
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { listing.applyFilterValues(draft.values); dismiss() }.disabled(!validDates).accessibilityIdentifier("promotions.filters.apply") }
                ToolbarItem { Button("Reset") { draft.clear() } }
            }
            .onAppear { if !seeded { draft.seed(listing.activeValues); seeded = true } }
            .sheet(isPresented: $channels) {
                CustomerEntitySelectionSheet(api: api, entity: "sales-channel", title: String(localized: "Sales channels"), multiple: true, selected: draft.optionsBinding("salesChannel").wrappedValue, sortField: "name") {
                    draft.optionsBinding("salesChannel").wrappedValue = $0
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 360, idealHeight: 580).presentationSizing(.fitted)
        #endif
    }
}
