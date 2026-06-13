import Foundation
import Observation
import ShopwareAdminAPI

/// Shared api/listing wiring for the listing screens; re-inits when the shop or its language
/// changes. Subclasses override `createListing(shop:api:)`. The Apple analogue of the Android
/// `ListingViewModel` base.
@MainActor
@Observable
class ListingViewModel<T> {
    let repo: AppRepository
    private(set) var api: ShopApi?
    private(set) var listing: ListingState<T>?

    @ObservationIgnored private var key: String?

    init(repo: AppRepository) {
        self.repo = repo
    }

    func start(_ shop: ConnectedShop) {
        let newKey = "\(shop.id)|\(shop.languageId ?? "")"
        if key == newKey { return }
        key = newKey
        let shopApi = repo.apiFor(shop)
        api = shopApi
        let state = createListing(shop: shop, api: shopApi)
        listing = state
        state.reload()
    }

    /// Subclasses build the listing's source/criteria/mapper/filters.
    func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<T> {
        fatalError("Subclasses must override createListing(shop:api:)")
    }
}
