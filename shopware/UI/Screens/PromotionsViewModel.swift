import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class PromotionsViewModel: ListingViewModel<PromotionItem> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<PromotionItem> {
        ListingState(filters: promotionFilters(), source: { try await api.repository("promotion").search($0) },
                     baseCriteria: { promotionListCriteria().addSorting("createdAt", "DESC") }, mapper: PromotionItem.init)
    }
}
