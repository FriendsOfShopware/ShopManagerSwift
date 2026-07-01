#if os(macOS)
import SwiftUI
import ShopwareAdminAPI

/// The macOS-native counterpart to `ListingScaffold`: a full-width, multi-column `Table` over a
/// `ListingState`, sharing the same search field, filter sheet, and quick chips. Selecting a row
/// (single click or ⏎) calls `onActivate`; right-click yields `rowMenu`. Generic over the caller's
/// `@TableColumnBuilder` so each screen defines meaningful columns.
struct MacListingTable<T: Identifiable, Columns: TableColumnContent, Menu: View>: View
where Columns.TableRowValue == T, Columns.TableColumnSortComparator == Never {
    @Bindable var state: ListingState<T>
    let api: ShopApi?
    var searchPrompt: LocalizedStringKey = "Search"
    var quickChips: [QuickChip] = []
    let onActivate: (T) -> Void
    @TableColumnBuilder<T, Never> let columns: () -> Columns
    @ViewBuilder let rowMenu: (T) -> Menu

    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var selectedID: T.ID?

    init(
        state: ListingState<T>,
        api: ShopApi?,
        searchPrompt: LocalizedStringKey = "Search",
        quickChips: [QuickChip] = [],
        onActivate: @escaping (T) -> Void,
        @TableColumnBuilder<T, Never> columns: @escaping () -> Columns,
        @ViewBuilder rowMenu: @escaping (T) -> Menu
    ) {
        self.state = state
        self.api = api
        self.searchPrompt = searchPrompt
        self.quickChips = quickChips
        self.onActivate = onActivate
        self.columns = columns
        self.rowMenu = rowMenu
    }

    var body: some View {
        VStack(spacing: 0) {
            if !quickChips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(quickChips) { chip in
                        FilterChip(label: chip.label, isOn: chip.isOn, action: chip.toggle)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            content

            Divider()
            footer
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

    @ViewBuilder
    private var content: some View {
        if let error = state.error, state.items.isEmpty {
            ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if state.items.isEmpty, !state.loading {
            ContentUnavailableView("Nothing here", systemImage: "tray", description: Text("No results match your filters."))
        } else {
            Table(state.items, selection: $selectedID, columns: columns)
                .contextMenu(forSelectionType: T.ID.self) { ids in
                    if let item = item(for: ids) { rowMenu(item) }
                } primaryAction: { ids in
                    if let item = item(for: ids) { onActivate(item) }
                }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if state.loading { ProgressView().controlSize(.small) }
            if state.total > 0 {
                Text("^[\(state.total) result](inflect: true)")
                    .foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            // Table has no per-row onAppear, so paging is an explicit action (no runaway fetch).
            if state.items.count < state.total {
                Button("Load more") { state.loadMore() }
                    .controlSize(.small)
                    .disabled(state.loading)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func item(for ids: Set<T.ID>) -> T? {
        guard let id = ids.first else { return nil }
        return state.items.first { $0.id == id }
    }
}
#endif
