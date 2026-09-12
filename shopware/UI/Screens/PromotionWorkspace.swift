import SwiftUI
import ShopwareAdminAPI

struct PromotionWorkspace: View {
    let shop: ConnectedShop
    @Bindable var listing: ListingState<PromotionItem>
    @Environment(AppViewModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var actions: PromotionActions
    @State private var wide = false
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var promotionID: String?
    @State private var sheet: PromotionListSheet?
    @State private var deleting = false
    @State private var sorting = [KeyPathComparator(\PromotionItem.createdOrder, order: .reverse)]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    init(shop: ConnectedShop, api: ShopApi, listing: ListingState<PromotionItem>) {
        self.shop = shop; self.listing = listing; _actions = State(initialValue: PromotionActions(api: api))
    }
    private var useTable: Bool {
        #if os(iOS)
        wide && sizeClass == .regular && !typeSize.isAccessibilitySize
        #else
        wide && !typeSize.isAccessibilitySize
        #endif
    }
    private var selectedUsed: Bool { listing.items.contains { selection.contains($0.id) && $0.orderCount > 0 } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if typeSize.isAccessibilitySize { availability.pickerStyle(.menu) }
                    else { availability.pickerStyle(.segmented).labelsHidden() }
                }.frame(maxWidth: 420)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = actions.permissionsError { PromotionNotice(message: error) { Task { await actions.loadPermissions() } } }
            if let error = actions.currencyError { PromotionNotice(message: error) { Task { await actions.loadCurrency() } } }
            if let error = listing.error, !listing.items.isEmpty { PromotionNotice(message: error) { listing.reload() } }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if listing.loading || actions.busy { ProgressView().controlSize(.small) }
                Text(selection.isEmpty ? String(localized: "\(listing.total) promotions") : String(localized: "\(selection.count) selected"))
                    .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("promotions.count")
                Spacer()
                if !selection.isEmpty && actions.permissions.allows("promotion:delete") {
                    Button("Delete…", role: .destructive) { deleting = true }.disabled(actions.busy || selectedUsed)
                        .help("Redeemed promotions cannot be deleted.").accessibilityIdentifier("promotions.deleteSelected")
                }
                if listing.items.count < listing.total { Button("Load more") { listing.loadMore() }.disabled(listing.loading).accessibilityIdentifier("promotions.loadMore") }
            }.padding(.horizontal, 16).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 850 } action: { wide = $0 }
        .searchable(text: $search, prompt: "Search promotions")
        .task(id: search) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard search != listing.term else { return }
                selection = []; listing.setTerm(search); listing.search()
            } catch { }
        }
        .task { await actions.loadPermissions() }
        .onChange(of: listing.activeValues) { selection = [] }
        .onChange(of: sorting) { applySorting() }
        .onChange(of: promotionID) { old, new in if old != nil && new == nil { selection = []; listing.reload() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New promotion", systemImage: "plus") { sheet = .create }.disabled(!actions.canCreate).accessibilityIdentifier("promotions.create")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Filters", systemImage: listing.activeFilterCount == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") { sheet = .filters }
                    .badge(listing.activeFilterCount).accessibilityIdentifier("promotions.filters")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if actions.permissions.allows("promotion:delete") {
                        Button(selecting ? "Done selecting" : "Select promotions") { selecting.toggle(); selection = [] }
                        Button("Select unused promotions") { selection = Set(listing.items.filter { $0.orderCount == 0 }.map(\.id)); selecting = true }.accessibilityIdentifier("promotions.selectUnused")
                        Button("Clear selection") { selection = [] }.disabled(selection.isEmpty)
                        Divider()
                    }
                    Menu("Sort promotions") {
                        Button("Newest first") { sorting = [KeyPathComparator(\PromotionItem.createdOrder, order: .reverse)] }
                        Button("Name") { sorting = [KeyPathComparator(\PromotionItem.name)] }
                        Button("Highest priority") { sorting = [KeyPathComparator(\PromotionItem.priority, order: .reverse)] }
                        Button("Most redeemed") { sorting = [KeyPathComparator(\PromotionItem.orderCount, order: .reverse)] }
                    }
                    Button("Refresh promotions", systemImage: "arrow.clockwise") { listing.reload() }.disabled(listing.loading)
                } label: { Label("Promotion list actions", systemImage: "ellipsis.circle") }
                .disabled(actions.busy).accessibilityIdentifier("promotions.actions")
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .filters: PromotionFilterSheet(listing: listing, api: actions.api)
            case .create: PromotionEditorSheet(promotion: nil, fields: [], actions: actions) { id in
                listing.reload(); model.refresh(shop.id); promotionID = id
            }
            }
        }
        .navigationDestination(item: $promotionID) { PromotionDetailView(shop: shop, promotionID: $0) }
        .confirmationDialog("Delete selected promotions?", isPresented: $deleting, titleVisibility: .visible) {
            Button(selection.count == 1 ? String(localized: "Delete promotion") : String(localized: "Delete \(selection.count) promotions"), role: .destructive) { Task { await deleteSelection() } }
        } message: { Text("Their discounts and individual codes will also be permanently deleted.") }
        .alert("Couldn't update promotions", isPresented: Binding(get: { actions.error != nil && sheet == nil }, set: { if !$0 { actions.error = nil } })) {
            Button("OK", role: .cancel) { actions.error = nil }
        } message: { Text(actions.error ?? "") }
    }
    private var availability: some View {
        Picker("Promotion availability", selection: Binding(get: { listing.activeValues["active"]?.promotionEnabledFilter ?? "all" }, set: {
                    selection = []; listing.setFilterValue("active", $0 == "all" ? nil : .options([$0]))
                })) {
                    Text("All promotions").tag("all"); Text("Enabled").tag("true"); Text("Disabled").tag("false")
                }.accessibilityIdentifier("promotions.availability")
    }
    @ViewBuilder private var content: some View {
        if listing.items.isEmpty && listing.loading { ProgressView("Loading promotions…") }
        else if listing.items.isEmpty, let error = listing.error {
            ContentUnavailableView { Label("Couldn't load promotions", systemImage: "exclamationmark.triangle") }
            description: { Text(error) } actions: { Button("Retry") { listing.reload() } }
        } else if listing.items.isEmpty {
            ContentUnavailableView {
                Label(listing.activeFilterCount == 0 && listing.term.isEmpty ? "No promotions yet" : "No matching promotions", systemImage: "tag")
            } description: { Text("Manage discounts and promotion codes for your shop.") }
            actions: {
                if listing.activeFilterCount > 0 { Button("Clear filters") { listing.applyFilterValues([:]) } }
                else if actions.canCreate { Button("New promotion…") { sheet = .create } }
            }
        } else if useTable { table }
        else {
            List(listing.items) { item in
                Button {
                    if selecting { if !selection.insert(item.id).inserted { selection.remove(item.id) } }
                    else { promotionID = item.id }
                } label: {
                    HStack(alignment: .top) {
                        if selecting { Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
                        PromotionListRow(promotion: item, currency: actions.currencyCode)
                        if !selecting { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
                    }.contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("promotions.row.\(item.id)")
                .contextMenu { rowActions(item) }
            }.refreshable { listing.reload(); await listing.fetchTask?.value }
        }
    }
    private var table: some View {
        Table(listing.items, selection: $selection, sortOrder: $sorting) {
            TableColumn("Promotion", value: \.name) { item in
                Button { promotionID = item.id } label: { Text(item.name).fontWeight(.medium).lineLimit(2) }
                    .buttonStyle(.plain).accessibilityIdentifier("promotions.row.\(item.id)")
            }.width(min: 160, ideal: 230)
            TableColumn("Status") { PromotionStatusLabel(state: $0.state()) }.width(min: 90, ideal: 100)
            TableColumn("Discount") { PromotionDiscountText(discounts: $0.discounts, currency: actions.currencyCode).lineLimit(2) }.width(min: 100, ideal: 140)
            TableColumn("Starts", value: \.fromOrder) { PromotionDateLabel(date: $0.validFrom) }.width(min: 85, ideal: 100)
            TableColumn("Ends", value: \.untilOrder) { PromotionDateLabel(date: $0.validUntil) }.width(min: 85, ideal: 100)
            TableColumn("Redemptions", value: \.orderCount) { Text($0.orderCount, format: .number) }.width(min: 85, ideal: 100)
            TableColumn("Priority", value: \.priority) { Text($0.priority, format: .number) }.width(65)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let item = listing.items.first(where: { ids.contains($0.id) }) { rowActions(item) }
        } primaryAction: { ids in if ids.count == 1 { promotionID = ids.first } }
    }
    @ViewBuilder private func rowActions(_ item: PromotionItem) -> some View {
        Button("Open promotion") { promotionID = item.id }
        if actions.canEdit {
            Button(item.active ? "Deactivate" : "Activate", systemImage: item.active ? "pause.circle" : "play.circle") {
                Task { if await actions.setActive(id: item.id, active: !item.active) { listing.reload(); model.refresh(shop.id) } }
            }
        }
        if actions.canDelete { Button("Delete promotion…", role: .destructive) { selection = [item.id]; deleting = true }.disabled(item.orderCount > 0) }
    }
    private func deleteSelection() async {
        let succeeded = await actions.delete(ids: selection)
        selection.subtract(succeeded)
        if selection.isEmpty { selecting = false }
        listing.removeItem { succeeded.contains($0.id) }
        if !succeeded.isEmpty { listing.reload(); model.refresh(shop.id) }
    }
    private func applySorting() {
        selection = []
        let fields: [PartialKeyPath<PromotionItem>: String] = [\PromotionItem.name: "name", \PromotionItem.priority: "priority", \PromotionItem.orderCount: "orderCount", \PromotionItem.createdOrder: "createdAt", \PromotionItem.fromOrder: "validFrom", \PromotionItem.untilOrder: "validUntil"]
        listing.setSorting(sorting.compactMap { sort in fields[sort.keyPath].map { ListingSort(field: $0, ascending: sort.order != .reverse) } })
    }
}

private enum PromotionListSheet: String, Identifiable { case filters, create; var id: String { rawValue } }
private extension FilterValue {
    var promotionEnabledFilter: String? { if case .options(let ids) = self { return ids.first }; return nil }
}
