import Foundation
import Observation
import ShopwareAdminAPI

@MainActor
@Observable
final class CustomersViewModel: ListingViewModel<CustomerRow> {
    private(set) var permissions = AdminPermissions()
    private(set) var permissionsError: String?

    override func createListing(shop: ConnectedShop, api: ShopApi) -> ListingState<CustomerRow> {
        permissions = AdminPermissions()
        return ListingState(filters: customerFilters(), source: { try await api.repository("customer").search($0) },
                            baseCriteria: customerManagementCriteria, mapper: parseCustomerRow)
    }

    func loadPermissions() async {
        guard let api else { return }
        permissionsError = nil
        do {
            let loaded = try await api.customers.permissions()
            guard self.api === api else { return }
            permissions = loaded
        } catch {
            guard self.api === api else { return }
            permissions = AdminPermissions()
            permissionsError = String(localized: "Couldn't load permissions. Retry to enable customer actions.")
        }
    }
}
