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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Reject", systemImage: "xmark") {
                                setStatus(listing: listing, review: review, approved: false)
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Approve", systemImage: "checkmark") {
                                setStatus(listing: listing, review: review, approved: true)
                            }
                            .tint(Theme.accent)
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
            } catch {
                // Leave the row in place on failure; the user can retry.
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

/// Five-star rating display (filled up to `points`).
struct StarRating: View {
    let points: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 5, id: \.self) { i in
                Image(systemName: i < points ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(i < points ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            }
        }
    }
}
