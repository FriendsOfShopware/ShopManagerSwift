import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct CustomerListActionsTests {
    @Test func refreshedResultsCannotLeaveInvisibleCustomersSelected() async {
        let listing = ListingState<CustomerRow>(
            source: { _ in SearchResult(total: 2, data: [
                SwEntity(.object(["id": "first", "firstName": "Ada", "lastName": "Lovelace"])),
                SwEntity(.object(["id": "second", "firstName": "Grace", "lastName": "Hopper"]))
            ], aggregations: .object([:])) }, baseCriteria: { Criteria() }, mapper: parseCustomerRow)
        listing.reload()
        await listing.fetchTask?.value

        let actions = CustomerListActions()
        actions.selection = ["first", "second", "no-longer-visible"]
        actions.reconcile(with: listing)
        #expect(actions.selection == ["first", "second"])
        actions.edit(actions.selection, in: listing)
        #expect(actions.bulkCustomers.map(\.id) == ["first", "second"])

        listing.removeItem { $0.id == "first" }
        actions.reconcile(with: listing)
        #expect(actions.selection == ["second"])
        // An already presented edit retains its explicit original customer set.
        #expect(actions.bulkCustomers.map(\.id) == ["first", "second"])
    }

    @Test func emptySelectionDoesNotPresentBulkEditor() async {
        let listing = ListingState<CustomerRow>(source: { _ in SearchResult(total: 0, data: [], aggregations: .object([:])) },
                                                 baseCriteria: { Criteria() }, mapper: parseCustomerRow)
        let actions = CustomerListActions()
        actions.edit(["stale-customer"], in: listing)
        #expect(!actions.bulkEditing)
        #expect(actions.bulkCustomers.isEmpty)
    }
}
