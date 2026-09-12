import SwiftUI
import ShopwareAdminAPI

struct ReviewWorkspace: View {
    let shop: ConnectedShop
    @Bindable var listing: ListingState<ReviewItem>
    @Environment(AppViewModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var actions: ReviewActions
    @State private var width: CGFloat = 0
    @State private var search = ""
    @State private var filters = false
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var reviewID: String?
    @State private var deleting = false
    @State private var sorting = [KeyPathComparator(\ReviewItem.statusOrder)]

    init(shop: ConnectedShop, api: ShopApi, listing: ListingState<ReviewItem>) {
        self.shop = shop; self.listing = listing
        _actions = State(initialValue: ReviewActions(api: api))
    }
    private var useTable: Bool { width >= 850 && !typeSize.isAccessibilitySize }
    private var status: String {
        listing.activeValues["status"] == .options(["true"]) ? "approved" : listing.activeValues["status"] == .options(["false"]) ? "pending" : "all"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if typeSize.isAccessibilitySize { approvalPicker.pickerStyle(.menu) }
                    else { approvalPicker.pickerStyle(.segmented).labelsHidden() }
                }.frame(maxWidth: 420).accessibilityIdentifier("reviews.approval")
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = actions.permissionsError { ReviewErrorBanner(message: error) { Task { await actions.loadPermissions() } } }
            if let error = listing.error, !listing.items.isEmpty { ReviewErrorBanner(message: error) { listing.reload() } }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if listing.loading || actions.busy { ProgressView().controlSize(.small) }
                Text(selection.isEmpty ? String(localized: "\(listing.total) reviews") : String(localized: "\(selection.count) selected"))
                    .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("reviews.count")
                Spacer()
                if !selection.isEmpty && actions.permissions.allows("product_review:delete") {
                    Button("Delete…", role: .destructive) { deleting = true }.disabled(actions.busy)
                        .accessibilityIdentifier("reviews.deleteSelected")
                }
                if listing.items.count < listing.total {
                    Button("Load more") { listing.loadMore() }.disabled(listing.loading || actions.busy).accessibilityIdentifier("reviews.loadMore")
                }
            }.padding(.horizontal, 16).padding(.vertical, 10).fixedSize(horizontal: false, vertical: true)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .searchable(text: $search, prompt: "Search reviews")
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
        .onChange(of: reviewID) { old, new in if old != nil && new == nil { selection = []; listing.reload() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Filters", systemImage: listing.activeFilterCount == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") { filters = true }
                    .badge(listing.activeFilterCount).accessibilityIdentifier("reviews.filters")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if actions.permissions.allows("product_review:delete") {
                        Button(selecting ? "Done selecting" : "Select reviews") { selecting.toggle(); selection = [] }
                        Button("Select loaded reviews") { selection = Set(listing.items.map(\.id)); selecting = true }.accessibilityIdentifier("reviews.selectLoaded")
                        Button("Clear selection") { selection = [] }.disabled(selection.isEmpty)
                        Divider()
                    }
                    Menu("Sort reviews") {
                        Button("Pending first") { sorting = [KeyPathComparator(\ReviewItem.statusOrder)] }
                        Button("Newest first") { sorting = [KeyPathComparator(\ReviewItem.dateOrder, order: .reverse)] }
                        Button("Oldest first") { sorting = [KeyPathComparator(\ReviewItem.dateOrder)] }
                        Button("Highest rating") { sorting = [KeyPathComparator(\ReviewItem.points, order: .reverse)] }
                        Button("Lowest rating") { sorting = [KeyPathComparator(\ReviewItem.points)] }
                    }
                    Button("Refresh reviews", systemImage: "arrow.clockwise") { listing.reload() }.disabled(listing.loading)
                } label: { Label("Review list actions", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("reviews.actions").disabled(actions.busy)
            }
        }
        .sheet(isPresented: $filters) { ReviewFilterSheet(listing: listing, api: actions.api) }
        .navigationDestination(item: $reviewID) { ReviewDetailView(shop: shop, reviewID: $0) }
        .confirmationDialog("Delete selected reviews?", isPresented: $deleting, titleVisibility: .visible) {
            Button(selection.count == 1 ? String(localized: "Delete review") : String(localized: "Delete \(selection.count) reviews"), role: .destructive) { Task { await deleteSelection() } }
        } message: { Text("The reviews and their public replies will be permanently deleted.") }
        .alert("Couldn't update reviews", isPresented: Binding(get: { actions.error != nil }, set: { if !$0 { actions.error = nil } })) {
            Button("OK", role: .cancel) { actions.error = nil }
        } message: { Text(actions.error ?? "") }
    }

    private var approvalPicker: some View {
        Picker("Approval", selection: Binding(get: { status }, set: {
            selection = []
            listing.setFilterValue("status", $0 == "all" ? nil : .options([$0 == "approved" ? "true" : "false"]))
        })) {
            Text("All reviews").tag("all")
            Text("Pending").tag("pending")
            Text("Approved").tag("approved")
        }
    }

    @ViewBuilder private var content: some View {
        if listing.items.isEmpty && listing.loading { ProgressView("Loading reviews…") }
        else if listing.items.isEmpty, let error = listing.error {
            ContentUnavailableView {
                Label("Couldn't load reviews", systemImage: "exclamationmark.bubble")
            } description: { Text(error) } actions: { Button("Retry") { listing.reload() } }
        }
        else if listing.items.isEmpty {
            ContentUnavailableView {
                Label(listing.activeFilterCount == 0 && listing.term.isEmpty ? "No reviews yet" : "No matching reviews", systemImage: "star.bubble")
            } description: { Text("Customer product reviews will appear here.") }
            actions: {
                if listing.activeFilterCount > 0 { Button("Clear filters") { listing.applyFilterValues([:]) } }
            }
        } else if useTable { table }
        else {
            List(listing.items) { review in
                Button {
                    if selecting { if !selection.insert(review.id).inserted { selection.remove(review.id) } }
                    else { reviewID = review.id }
                } label: {
                    HStack(alignment: .top) {
                        if selecting { Image(systemName: selection.contains(review.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint) }
                        ReviewListRow(review: review)
                        if !selecting { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
                    }.contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("reviews.row.\(review.id)")
                .contextMenu { rowActions(review) }
                #if os(iOS)
                .swipeActions(edge: .leading) {
                    if actions.canEdit { Button(review.approved ? "Hide review" : "Approve", systemImage: review.approved ? "eye.slash" : "checkmark") { moderate(review) }.tint(Theme.accent) }
                }
                #endif
            }.refreshable { listing.reload(); await listing.fetchTask?.value }
        }
    }
    private var table: some View {
        Table(listing.items, selection: $selection, sortOrder: $sorting) {
            TableColumn("Review", value: \.title) { review in
                Button { reviewID = review.id } label: {
                    Text(review.title).fontWeight(.medium).lineLimit(2)
                }.buttonStyle(.plain).help(review.title).accessibilityIdentifier("reviews.row.\(review.id)")
            }.width(min: 160, ideal: 220)
            TableColumn("Rating", value: \.points) { ReviewRating(points: $0.points) }.width(100)
            TableColumn("Product", value: \.productName) { Text($0.productName).lineLimit(2) }.width(min: 110, ideal: 150)
            TableColumn("Customer", value: \.reviewer) { Text($0.reviewer).lineLimit(2) }.width(min: 110, ideal: 140)
            TableColumn("Date", value: \.dateOrder) { ReviewDate(date: $0.createdAt) }.width(min: 85, ideal: 95)
            TableColumn("Approval", value: \.statusOrder) { ReviewStatus(approved: $0.approved) }.width(min: 80, ideal: 90)
            TableColumn("Reply") { if $0.hasReply { Image(systemName: "text.bubble.fill").foregroundStyle(.secondary).accessibilityLabel("Replied") } else { Text("—").accessibilityLabel("No reply") } }.width(50)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let review = listing.items.first(where: { ids.contains($0.id) }) { rowActions(review) }
            else if actions.canDelete { Button("Delete selected reviews…", role: .destructive) { selection = ids; deleting = true }.disabled(ids.isEmpty) }
        } primaryAction: { ids in if ids.count == 1 { reviewID = ids.first } }
    }
    @ViewBuilder private func rowActions(_ review: ReviewItem) -> some View {
        Button("Open review") { reviewID = review.id }
        if actions.canEdit { Button(review.approved ? "Hide review" : "Approve", systemImage: review.approved ? "eye.slash" : "checkmark") { moderate(review) } }
        if actions.canDelete { Button("Delete review…", role: .destructive) { selection = [review.id]; deleting = true } }
    }
    private func moderate(_ review: ReviewItem) {
        Task {
            guard await actions.approve(id: review.id, approved: !review.approved) else { return }
            // Reload so every active filter and server-side sorting is reapplied.
            selection = []; listing.reload(); model.refresh(shop.id)
        }
    }
    private func deleteSelection() async {
        let succeeded = await actions.delete(ids: selection)
        selection.subtract(succeeded)
        listing.removeItem { succeeded.contains($0.id) }
        if !succeeded.isEmpty { listing.reload(); model.refresh(shop.id) }
    }
    private func applySorting() {
        selection = []
        let fields: [PartialKeyPath<ReviewItem>: String] = [\ReviewItem.title: "title", \ReviewItem.points: "points", \ReviewItem.productName: "product.name", \ReviewItem.reviewer: "customer.lastName", \ReviewItem.dateOrder: "createdAt", \ReviewItem.statusOrder: "status"]
        var order = sorting.compactMap { sort in fields[sort.keyPath].map { ListingSort(field: $0, ascending: sort.order != .reverse) } }
        if order.first?.field == "status", !order.contains(where: { $0.field == "createdAt" }) {
            order.append(ListingSort(field: "createdAt", ascending: false))
        }
        listing.setSorting(order)
    }
}
