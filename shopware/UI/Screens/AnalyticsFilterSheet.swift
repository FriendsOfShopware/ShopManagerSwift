import SwiftUI

/// Multi-select filter sheet for the analytics KPIs: each of the six dimensions pushes a checkmark
/// list (Settings style) and shows the current selection. "Apply" commits, "Reset" clears.
struct AnalyticsFilterSheet: View {
    let options: AnalyticsFilterOptions
    let filters: AnalyticsFilters
    let onApply: (AnalyticsFilters) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AnalyticsFilters

    init(options: AnalyticsFilterOptions, filters: AnalyticsFilters, onApply: @escaping (AnalyticsFilters) -> Void) {
        self.options = options
        self.filters = filters
        self.onApply = onApply
        _draft = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                dimension("Sales channel", options.salesChannels, selection: $draft.salesChannelIds)
                dimension("Order status", options.orderStates, selection: $draft.orderStateIds)
                dimension("Payment status", options.paymentStates, selection: $draft.paymentStateIds)
                dimension("Delivery status", options.deliveryStates, selection: $draft.deliveryStateIds)
                dimension("Customer group", options.customerGroups, selection: $draft.customerGroupIds)
                dimension("Country", options.countries, selection: $draft.countryIds)
            }
            .groupedFormStyle()
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        draft.salesChannelIds = []; draft.orderStateIds = []; draft.paymentStateIds = []
                        draft.deliveryStateIds = []; draft.customerGroupIds = []; draft.countryIds = []
                        onApply(draft)
                        dismiss()
                    }
                    .disabled(draft.activeCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(draft); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #else
        .presentationDetents([.medium, .large])
        #endif
        .acceptsFirstMouse()
    }

    @ViewBuilder
    private func dimension(_ label: LocalizedStringKey, _ items: [FilterOptionItem], selection: Binding<[String]>) -> some View {
        if !items.isEmpty {
            Section {
                NavigationLink {
                    DimensionSelectionList(title: label, items: items, selection: selection)
                } label: {
                    LabeledContent(label, value: summary(selection.wrappedValue, items))
                }
            }
        }
    }

    private func summary(_ ids: [String], _ items: [FilterOptionItem]) -> String {
        if ids.isEmpty { return String(localized: "Any") }
        if ids.count == 1, let match = items.first(where: { $0.id == ids[0] }) { return match.label }
        return String(localized: "\(ids.count) selected")
    }
}

/// The pushed checkmark list for one analytics dimension.
private struct DimensionSelectionList: View {
    let title: LocalizedStringKey
    let items: [FilterOptionItem]
    @Binding var selection: [String]

    var body: some View {
        Form {
            if !selection.isEmpty {
                Section {
                    Button("Clear selection", role: .destructive) { selection = [] }
                }
            }
            Section {
                ForEach(items) { item in
                    Button {
                        if let idx = selection.firstIndex(of: item.id) {
                            selection.remove(at: idx)
                        } else {
                            selection.append(item.id)
                        }
                    } label: {
                        HStack {
                            Text(item.label).foregroundStyle(.primary)
                            Spacer()
                            if selection.contains(item.id) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .groupedFormStyle()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
