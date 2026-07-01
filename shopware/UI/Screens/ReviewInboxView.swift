import SwiftUI
import ShopwareAdminAPI

@MainActor
@Observable
final class ReviewInboxViewModel: ListingViewModel<ReviewItem> {
    /// Quick chips for the inbox: Pending first (the default), then Approved.
    let quickFilters: [QuickFilter] = [
        QuickFilter(key: "status", label: "Pending", value: .options(["false"])),
        QuickFilter(key: "status", label: "Approved", value: .options(["true"])),
    ]

    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<ReviewItem> {
        let filters: [ListingFilter] = [
            .bool(key: "status", label: "Status", field: "status",
                  trueLabel: "Approved", falseLabel: "Pending"),
            salesChannelFilter(label: "Sales channel"),
        ]

        let state = ListingState(
            filters: filters,
            source: { try await api.repository("product-review").search($0) },
            baseCriteria: {
                Criteria()
                    .addSorting("createdAt", "DESC")
                    .addAssociation("product")
                    .addAssociation("customer")
                    .addIncludes("product_review", [
                        "id", "title", "content", "points", "status",
                        "createdAt", "externalUser", "product", "customer",
                    ])
                    .addIncludes("product", ["name", "translated"])
                    .addIncludes("customer", ["firstName", "lastName"])
            },
            mapper: { r in
                let customer = r.entity("customer")
                let name = [customer?.string("firstName"), customer?.string("lastName")]
                    .compactMap { $0 }
                let reviewer = name.isEmpty
                    ? (r.string("externalUser") ?? "Guest")
                    : name.joined(separator: " ")
                return ReviewItem(
                    id: r.id ?? "",
                    title: r.string("title") ?? "—",
                    content: r.string("content") ?? "",
                    points: Int(r.double("points") ?? 0),
                    approved: r.boolean("status") ?? false,
                    reviewer: reviewer,
                    productName: r.entity("product")?.translated("name") ?? "—",
                    createdMs: r.date("createdAt")?.epochMs ?? Date().epochMs
                )
            }
        )
        // Default to the pending inbox. The base class's reload() after this returns is harmless
        // (same criteria), so we don't need to reload here.
        state.setFilterValue("status", .options(["false"]))
        return state
    }
}

/// The review inbox: a listing of product reviews with quick Pending/Approved chips and inline
/// approve/reject actions. Ported from the Android `ReviewInboxScreen`.
struct ReviewInboxView: View {
    let shop: ConnectedShop
    @Environment(AppViewModel.self) private var model
    @State private var vm: ReviewInboxViewModel?
    @State private var busyId: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                ListingScaffold(
                    state: listing,
                    api: vm.api,
                    searchPrompt: "Search reviews",
                    quickChips: chips(for: listing)
                ) { review in
                    ReviewCard(review: review)
                        #if os(iOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !review.approved {
                                Button("Approve", systemImage: "checkmark") {
                                    setStatus(listing: listing, review: review, approved: true)
                                }
                                .tint(Theme.accent)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // Pending → Reject; already-approved → Keep hidden (un-approve).
                            Button(review.approved ? "Keep hidden" : "Reject", systemImage: "xmark") {
                                setStatus(listing: listing, review: review, approved: false)
                            }
                            .tint(.red)
                        }
                        #endif
                        // Context menu mirrors the swipe actions and is the primary path on macOS.
                        .contextMenu {
                            if !review.approved {
                                Button("Approve", systemImage: "checkmark") {
                                    setStatus(listing: listing, review: review, approved: true)
                                }
                            }
                            Button(review.approved ? "Keep hidden" : "Reject", systemImage: "xmark", role: .destructive) {
                                setStatus(listing: listing, review: review, approved: false)
                            }
                        }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reviews")
        .onAppear {
            if vm == nil { vm = ReviewInboxViewModel(repo: model.repo) }
            vm?.start(shop)
        }
        .alert("Couldn't update review", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func chips(for listing: ListingState<ReviewItem>) -> [QuickChip] {
        (vm?.quickFilters ?? []).map { qf in
            let isOn = listing.activeValues[qf.key] == qf.value
            return QuickChip(label: qf.label, isOn: isOn) {
                listing.setFilterValue(qf.key, isOn ? nil : qf.value)
            }
        }
    }

    /// Approves/rejects a review, then drops it from the list if its new status no longer matches
    /// the active status filter (mirrors the Android optimistic removal).
    private func setStatus(listing: ListingState<ReviewItem>, review: ReviewItem, approved: Bool) {
        if busyId != nil { return }
        busyId = review.id
        Task {
            defer { busyId = nil }
            do {
                try await model.repo.setReviewStatus(shop, reviewId: review.id, approved: approved)
                let active = listing.activeValues["status"]
                if (active == .options(["false"]) && approved)
                    || (active == .options(["true"]) && !approved) {
                    listing.removeItem(where: { $0.id == review.id })
                }
                model.refresh(shop.id) // keep the pending-reviews count / Home hero current
            } catch {
                actionError = (error as? ApiError)?.message ?? error.localizedDescription
            }
        }
    }
}

/// A single review row: star rating + age, title, product/reviewer caption, and the content.
/// Approve/reject are swipe actions (applied by the list) — the native gesture for row actions.
private struct ReviewCard: View {
    let review: ReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                StarRating(points: review.points)
                Spacer()
                StatusBadge(label: review.approved ? "Approved" : "Pending",
                            tone: review.approved ? .done : .warning)
                Text(relativeAgoText(review.createdMs))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(review.title).font(.body.weight(.medium))

            Text("\(review.productName) · \(review.reviewer)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !review.content.isEmpty {
                Text(review.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}
