import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class ProductsViewModel: ListingViewModel<ProductItem> {
    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<ProductItem> {
        ListingState(filters: productWorkspaceFilters(), source: { criteria in
            // A tie-breaker prevents duplicate or missing rows across page boundaries.
            try await api.repository("product").search(criteria.addSorting("id"))
        }, baseCriteria: { productWorkspaceCriteria() }, mapper: { ProductItem($0, shopURL: shop.baseUrl) })
    }
}
