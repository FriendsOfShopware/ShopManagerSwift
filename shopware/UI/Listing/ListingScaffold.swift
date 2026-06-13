import SwiftUI
import ShopwareAdminAPI

/// Reusable listing UI: a searchable `List` over a `ListingState`, with a filter sheet, active-
/// filter count, quick chips, results count, infinite scroll, and empty/error/loading states.
/// The Apple-HIG analogue of the Android `ListingScaffold` (admin sw-filter-panel pattern).
struct ListingScaffold<T: Identifiable, Row: View, Header: View>: View {
    @Bindable var state: ListingState<T>
    let api: ShopApi?
    var searchPrompt: LocalizedStringKey = "Search"
    /// Quick toggle chips shown above the list (e.g. Active/Inactive).
    var quickChips: [QuickChip] = []
    @ViewBuilder var header: () -> Header
    @ViewBuilder var row: (T) -> Row

    @State private var searchText = ""
    @State private var showingFilters = false

    var body: some View {
        List {
            header()

            if !quickChips.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        // Group the glass chips in one container so they sample consistently.
                        GlassEffectContainer(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(quickChips) { chip in
                                    FilterChip(label: chip.label, isOn: chip.isOn, action: chip.toggle)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if let error = state.error, state.items.isEmpty {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
                    .listRowSeparator(.hidden)
            } else if state.items.isEmpty, !state.loading {
                ContentUnavailableView("Nothing here", systemImage: "tray", description: Text("No results match your filters."))
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(state.items) { item in
                        row(item)
                            .onAppear {
                                if item.id == state.items.last?.id { state.loadMore() }
                            }
                    }
                } footer: {
                    if state.loading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if state.total > 0 {
                        Text("\(state.total) result\(state.total == 1 ? "" : "s")")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .onSubmit(of: .search) {
            state.setTerm(searchText)
            state.search()
        }
        .onChange(of: searchText) { _, new in
            if new.isEmpty, !state.term.isEmpty {
                state.setTerm("")
                state.search()
            }
        }
        .refreshable { state.reload() }
        .toolbar {
            if !state.filters.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filters", systemImage: state.activeFilterCount > 0
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .badge(state.activeFilterCount)
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(state: state, api: api)
        }
    }
}

// Convenience initializers for omitting the header.
extension ListingScaffold where Header == EmptyView {
    init(
        state: ListingState<T>,
        api: ShopApi?,
        searchPrompt: LocalizedStringKey = "Search",
        quickChips: [QuickChip] = [],
        @ViewBuilder row: @escaping (T) -> Row
    ) {
        self.init(
            state: state, api: api, searchPrompt: searchPrompt, quickChips: quickChips,
            header: { EmptyView() }, row: row
        )
    }
}

struct QuickChip: Identifiable {
    let id = UUID()
    let label: LocalizedStringKey
    let isOn: Bool
    let toggle: () -> Void
}

struct FilterChip: View {
    let label: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? Theme.onAccentContainer : .primary)
        }
        .buttonStyle(.plain)
        .modifier(ChipBackground(isOn: isOn))
    }
}

/// Selected chips read as a solid accent fill; unselected chips float as Liquid Glass.
private struct ChipBackground: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.background(Theme.accentContainer, in: Capsule())
        } else {
            content.glassEffect(.regular, in: .capsule)
        }
    }
}
