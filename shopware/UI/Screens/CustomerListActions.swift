import Foundation
import Observation
import ShopwareAdminAPI

/// Shared selection and mutation state for the desktop table and mobile list.
@MainActor
@Observable
final class CustomerListActions {
    var selection = Set<String>()
    var deleteIDs: [String] = []
    var bulkCustomers: [CustomerRow] = []
    var creating = false
    var bulkEditing = false
    var error: String?
    private(set) var busy = false

    func edit(_ ids: Set<String>, in listing: ListingState<CustomerRow>) {
        bulkCustomers = listing.items.filter { ids.contains($0.id) }
        bulkEditing = !bulkCustomers.isEmpty
    }

    func reconcile(with listing: ListingState<CustomerRow>) {
        selection.formIntersection(Set(listing.items.map(\.id)))
    }

    func deleteCustomers(vm: CustomersViewModel, listing: ListingState<CustomerRow>) {
        guard !busy, vm.permissions.allows("customer:delete"), let api = vm.api, !deleteIDs.isEmpty else { return }
        let ids = deleteIDs
        deleteIDs = []
        busy = true
        Task {
            defer { busy = false }
            do {
                try await api.customers.bulkDelete(ids)
                selection.subtract(ids)
                listing.reload()
            } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
