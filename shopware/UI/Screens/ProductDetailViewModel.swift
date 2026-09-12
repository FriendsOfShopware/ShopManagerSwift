import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class ProductDetailViewModel {
    let shop: ConnectedShop
    let id: String
    let actions: ProductActions
    let variants: ListingState<ProductItem>
    private(set) var product: ProductItem?
    private(set) var fields: [CustomerCustomFieldSet] = []
    private(set) var fieldsError: String?
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private var generation = 0
    init(api: ShopApi, shop: ConnectedShop, id: String) {
        self.shop = shop; self.id = id; actions = ProductActions(api: api)
        variants = ListingState(source: { try await api.repository("product").search($0.addSorting("id")) },
                                baseCriteria: { productWorkspaceCriteria(parentID: id) }, mapper: { ProductItem($0, shopURL: shop.baseUrl) })
    }
    func load() async {
        generation += 1; let token = generation
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        await actions.loadPermissions()
        do {
            let entity = try await actions.api.repository("product").get(id, criteria: productWorkspaceDetailCriteria())
            guard generation == token else { return }
            product = entity.map { ProductItem($0, shopURL: shop.baseUrl) }
            guard product != nil else { error = String(localized: "This product is no longer available."); return }
            await loadFields()
        } catch is CancellationError { }
        catch { if generation == token { self.error = (error as? ApiError)?.message ?? error.localizedDescription } }
    }
    func loadFields() async {
        fieldsError = nil
        guard actions.permissions.allows("custom_field_set:read") else { fields = []; return }
        do { fields = try await actions.api.customerCustomFieldSets(entity: "product", locale: shop.localeCode ?? Locale.current.identifier) }
        catch { fieldsError = error.localizedDescription }
    }
}
