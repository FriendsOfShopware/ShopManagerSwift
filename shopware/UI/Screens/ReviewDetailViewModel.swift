import SwiftUI
import ShopwareAdminAPI

@MainActor @Observable
final class ReviewDetailViewModel {
    let actions: ReviewActions
    let shop: ConnectedShop
    let reviewID: String
    private(set) var review: ReviewItem?
    private(set) var fields: [CustomerCustomFieldSet] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var fieldsError: String?
    @ObservationIgnored private var generation = 0

    init(api: ShopApi, shop: ConnectedShop, reviewID: String) {
        actions = ReviewActions(api: api); self.shop = shop; self.reviewID = reviewID
    }
    func load() async {
        generation += 1
        let token = generation
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        await actions.loadPermissions()
        do {
            let entity = try await actions.api.repository("product-review").get(reviewID, criteria: reviewCriteria())
            guard generation == token else { return }
            review = entity.map(ReviewItem.init)
            if entity == nil { error = String(localized: "This review is no longer available."); return }
            await loadFields()
        } catch is CancellationError { }
        catch { if generation == token { self.error = (error as? ApiError)?.message ?? error.localizedDescription } }
    }
    func loadFields() async {
        fieldsError = nil
        guard actions.permissions.allows("custom_field_set:read") else { fields = []; return }
        do { fields = try await actions.api.customerCustomFieldSets(entity: "product_review", locale: shop.localeCode ?? Locale.current.identifier) }
        catch { fieldsError = error.localizedDescription }
    }
}
