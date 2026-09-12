import SwiftUI
import ShopwareAdminAPI

@MainActor @Observable
final class ReviewInboxViewModel: ListingViewModel<ReviewItem> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<ReviewItem> {
        ListingState(filters: reviewFilters(), source: { try await api.repository("product-review").search($0) },
                     baseCriteria: { reviewCriteria().addSorting("status").addSorting("createdAt", "DESC") },
                     mapper: { ReviewItem($0) })
    }
}
