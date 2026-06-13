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
                    ReviewCard(
                        review: review,
                        busy: busyId == review.id,
                        approve: { setStatus(listing: listing, review: review, approved: true) },
                        reject: { setStatus(listing: listing, review: review, approved: false) }
                    )
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

/// A single review row: star rating, title, product/reviewer/age caption, content, and the
/// approve/reject actions.
private struct ReviewCard: View {
    let review: ReviewItem
    let busy: Bool
    let approve: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0 ..< min(review.points, 5), id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }

            Text(review.title)
                .font(.subheadline.weight(.semibold))

            Text("\(review.productName) · \(review.reviewer) · \(relativeAgoText(review.createdMs))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !review.content.isEmpty {
                Text(review.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Spacer()
                Button(action: reject) {
                    Label("Reject", systemImage: "xmark")
                }
                .tint(.red)
                Button(action: approve) {
                    Label("Approve", systemImage: "checkmark")
                }
                .tint(Theme.accent)
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .disabled(busy)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
