import SwiftUI
import ShopwareAdminAPI

struct CustomerEntitySelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let multiple: Bool
    let onApply: (Set<String>) -> Void
    @State private var selected: Set<String>
    @State private var listing: ListingState<CustomerOption>
    @State private var search = ""

    init(api: ShopApi, entity: String, title: String, multiple: Bool, selected: Set<String>, labelProperty: String? = nil, onApply: @escaping (Set<String>) -> Void) {
        self.title = title
        self.multiple = multiple
        self.onApply = onApply
        _selected = State(initialValue: selected)
        _listing = State(initialValue: ListingState(source: { try await api.repository(entity).search($0) },
                                                  baseCriteria: { Criteria().addSorting("id") },
                                                  mapper: { CustomerOption(id: $0.id ?? "", name: customerEntityLabel($0, property: labelProperty)) }))
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = listing.error {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { listing.reload() }
                }
                ForEach(listing.items) { item in
                    Button {
                        if selected.contains(item.id) { selected.remove(item.id) }
                        else if multiple { selected.insert(item.id) }
                        else { selected = [item.id] }
                    } label: {
                        HStack {
                            Text(item.name)
                            Spacer()
                            if selected.contains(item.id) { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                        }.contentShape(.rect)
                    }.buttonStyle(.plain)
                }
                if listing.loading { ProgressView() }
                else if listing.items.isEmpty { Text("No matching items").foregroundStyle(.secondary) }
                if listing.items.count < listing.total { Button("Load more") { listing.loadMore() }.disabled(listing.loading) }
            }
            .searchable(text: $search)
            .onSubmit(of: .search) { listing.setTerm(search); listing.search() }
            .onChange(of: search) { if search.isEmpty { listing.setTerm(""); listing.search() } }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply(selected); dismiss() } }
            }
            .task { listing.reload() }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 420, idealHeight: 560)
        #endif
    }
}
