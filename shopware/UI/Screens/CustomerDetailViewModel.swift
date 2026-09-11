import Foundation
import Observation
import ShopwareAdminAPI

@MainActor
@Observable
final class CustomerDetailViewModel {
    let api: ShopApi
    let shop: ConnectedShop
    let customerId: String
    private(set) var detail: CustomerDetail?
    private(set) var loading = false
    private(set) var busy = false
    private(set) var error: String?
    var actionError: String?
    private(set) var permissions = AdminPermissions()
    private(set) var orders: ListingState<RecentOrder>?
    let addresses: ListingState<EditableAddress>
    private(set) var customFieldSets: [CustomerCustomFieldSet] = []
    private(set) var addressCustomFieldSets: [CustomerCustomFieldSet] = []
    private(set) var orderTotalCount: Int?

    init(repo: AppRepository, shop: ConnectedShop, customerId: String) {
        self.api = repo.apiFor(shop)
        self.shop = shop
        self.customerId = customerId
        addresses = api.customerAddressListing(customerId: customerId)
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        do {
            detail = try await api.fetchCustomerDetail(customerId)
            guard detail != nil else {
                error = String(localized: "This customer no longer exists.")
                return
            }
            do {
                permissions = try await api.customers.permissions()
            } catch {
                permissions = AdminPermissions()
                actionError = String(localized: "Couldn't load permissions. Reload to enable customer actions.")
            }
            if !permissions.allows("order:read") { orders = nil }
            if orders == nil, permissions.allows("order:read") {
                orders = ListingState(
                    pageSize: 25,
                    source: { [api] in try await api.repository("order").search($0) },
                    baseCriteria: { [customerId] in
                        orderListCriteria().addFilter(Criteria.equals("orderCustomer.customerId", .string(customerId)))
                    }, mapper: { parseOrder($0, now: Date().epochMs) }
                )
            }
            orders?.reload()
            orderTotalCount = nil
            if permissions.allows("order:read") {
                orderTotalCount = try await api.repository("order").search(Criteria().setLimit(1).setTotalCountMode(.exact)
                    .addFilter(Criteria.equals("orderCustomer.customerId", .string(customerId))).addIncludes("order", ["id"])).total
            }
            customFieldSets = []
            addressCustomFieldSets = []
            if permissions.allows("custom_field_set:read") {
                customFieldSets = try await api.customerCustomFieldSets(entity: "customer", locale: shop.localeCode ?? "en-GB")
                addressCustomFieldSets = try await api.customerCustomFieldSets(entity: "customer_address", locale: shop.localeCode ?? "en-GB")
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    func perform(_ action: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        actionError = nil
        defer { busy = false }
        do {
            try await action()
            await load()
            addresses.reload()
            return true
        } catch {
            actionError = (error as? ApiError)?.message ?? error.localizedDescription
            return false
        }
    }

    func isDefaultAddress(_ id: String) -> Bool {
        detail?.defaultBillingAddressId == id || detail?.defaultShippingAddressId == id
    }
}
