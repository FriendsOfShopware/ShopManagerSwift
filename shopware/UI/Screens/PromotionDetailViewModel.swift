import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class PromotionDetailViewModel {
    let shop: ConnectedShop
    let id: String
    let actions: PromotionActions
    private(set) var promotion: PromotionItem?
    private(set) var fields: [CustomerCustomFieldSet] = []
    private(set) var exclusions: [PromotionReference] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var fieldsError: String?
    private(set) var exclusionsError: String?
    @ObservationIgnored private var generation = 0
    init(api: ShopApi, shop: ConnectedShop, id: String) {
        self.shop = shop; self.id = id; actions = PromotionActions(api: api)
    }
    func load() async {
        generation += 1; let token = generation
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        await actions.loadPermissions()
        do {
            let entity = try await actions.api.repository("promotion").get(id, criteria: promotionDetailCriteria())
            guard generation == token else { return }
            promotion = entity.map(PromotionItem.init)
            guard promotion != nil else { error = String(localized: "This promotion is no longer available."); return }
            await loadFields()
            await loadExclusions()
        } catch is CancellationError { }
        catch { if generation == token { self.error = (error as? ApiError)?.message ?? error.localizedDescription } }
    }
    func loadFields() async {
        fieldsError = nil
        guard actions.permissions.allows("custom_field_set:read") else { fields = []; return }
        do { fields = try await actions.api.customerCustomFieldSets(entity: "promotion", locale: shop.localeCode ?? Locale.current.identifier) }
        catch { fieldsError = error.localizedDescription }
    }
    func loadExclusions() async {
        exclusionsError = nil; exclusions = []
        guard let ids = promotion?.exclusionIDs, !ids.isEmpty else { return }
        do { exclusions = try await actions.api.repository("promotion").search(Criteria().setIds(ids.sorted()).setLimit(ids.count)).data.map(PromotionReference.init) }
        catch { exclusionsError = error.localizedDescription }
    }
}
