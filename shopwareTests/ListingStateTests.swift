import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

private struct NamedError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
struct ListingStateTests {
    /// Records each criteria the source received, as parsed JSON.
    final class Recorder {
        var received: [JSONValue] = []
    }

    private func result(_ total: Int, _ names: String...) -> SearchResult {
        SearchResult(
            total: total,
            data: names.map { SwEntity(.object(["name": .string($0)])) },
            aggregations: .object([:])
        )
    }

    private func makeState(
        recorder: Recorder,
        filters: [ListingFilter] = [],
        source: @escaping (Criteria) async throws -> SearchResult
    ) -> ListingState<NamedItem> {
        ListingState(
            pageSize: 2,
            filters: filters,
            source: { criteria in
                recorder.received.append(criteria.toJSON())
                return try await source(criteria)
            },
            baseCriteria: { Criteria().addSorting("orderDateTime", "DESC") },
            mapper: { NamedItem(name: $0.string("name") ?? "") }
        )
    }

    /// Awaits the in-flight fetch so assertions see settled state.
    private func settle(_ state: ListingState<NamedItem>) async {
        await state.fetchTask?.value
    }

    private func page(_ request: JSONValue) -> Int? { request["page"]?.intValue }

    @Test func firstLoadPopulatesItemsAndTotal() async {
        let rec = Recorder()
        let state = makeState(recorder: rec) { _ in self.result(5, "a", "b") }
        state.reload()
        await settle(state)

        #expect(state.items.map(\.name) == ["a", "b"])
        #expect(state.total == 5)
        #expect(state.error == nil)
        #expect(rec.received.count == 1)
        #expect(JSONValue.parse(#"{"page":1,"limit":2,"total-count-mode":1,"sort":[{"field":"orderDateTime","order":"DESC"}]}"#) == rec.received[0])
    }

    @Test func loadMoreAppendsAndStopsAtTotal() async {
        let rec = Recorder()
        let state = makeState(recorder: rec) { criteria in
            self.page(criteria.toJSON()) == 1 ? self.result(3, "a", "b") : self.result(3, "c")
        }
        state.reload(); await settle(state)
        state.loadMore(); await settle(state)

        #expect(state.items.map(\.name) == ["a", "b", "c"])
        #expect(rec.received.count == 2)
        #expect(page(rec.received.last!) == 2)

        state.loadMore(); await settle(state)
        #expect(rec.received.count == 2)
    }

    @Test func failingLoadMoreRestoresPage() async {
        let rec = Recorder()
        let failNext = Locked(false)
        let state = makeState(recorder: rec) { criteria in
            if failNext.value { failNext.value = false; throw NamedError(message: "boom") }
            return self.page(criteria.toJSON()) == 1 ? self.result(10, "a", "b") : self.result(10, "c", "d")
        }
        state.reload(); await settle(state)

        failNext.value = true
        state.loadMore(); await settle(state)
        #expect(state.error == "boom")
        #expect(state.items.map(\.name) == ["a", "b"])

        state.loadMore(); await settle(state)
        #expect(page(rec.received.last!) == 2)
        #expect(state.items.map(\.name) == ["a", "b", "c", "d"])
        #expect(state.error == nil)
    }

    @Test func setFilterValueReloadsWithMergedCriteria() async {
        let rec = Recorder()
        let filters: [ListingFilter] = [
            .options(key: "state", label: "Status", field: "stateMachineState.id"),
            .numberRange(key: "amount", label: "Amount", field: "amountTotal"),
        ]
        let state = makeState(recorder: rec, filters: filters) { _ in self.result(1, "a") }
        state.setTerm("hoodie")
        state.setFilterValue("state", .options(["s1"])); await settle(state)
        state.setFilterValue("amount", .range(min: 100.0, max: nil)); await settle(state)

        let request = rec.received.last!
        #expect(request["term"]?.stringValue == "hoodie")
        #expect(JSONValue.parse(#"[{"type":"equalsAny","field":"stateMachineState.id","value":["s1"]},{"type":"range","field":"amountTotal","parameters":{"gte":100.0}}]"#) == request["filter"])

        state.setFilterValue("state", nil); await settle(state)
        #expect(rec.received.last!["filter"]?.arrayValue?.count == 1)
        #expect(state.activeFilterCount == 1)

        state.applyFilterValues([:]); await settle(state)
        #expect(rec.received.last!["filter"] == nil)
        #expect(state.activeFilterCount == 0)
    }

    @Test func searchSendsTermAndResetsToFirstPage() async {
        let rec = Recorder()
        let state = makeState(recorder: rec) { _ in self.result(10, "a", "b") }
        state.reload(); await settle(state)
        state.loadMore(); await settle(state)

        state.setTerm("shirt")
        state.search(); await settle(state)

        let request = rec.received.last!
        #expect(page(request) == 1)
        #expect(request["term"]?.stringValue == "shirt")
    }

    @Test func mutateItemTransformsMatchingItem() async {
        let rec = Recorder()
        let state = makeState(recorder: rec) { _ in self.result(2, "a", "b") }
        state.reload(); await settle(state)

        state.mutateItem(where: { $0.name == "b" }, transform: { NamedItem(name: $0.name.uppercased()) })
        #expect(state.items.map(\.name) == ["a", "B"])
    }

    @Test func removeItemDropsMatchAndDecrementsTotal() async {
        let rec = Recorder()
        let state = makeState(recorder: rec) { _ in self.result(5, "a", "b") }
        state.reload(); await settle(state)

        state.removeItem(where: { $0.name == "a" })
        #expect(state.items.map(\.name) == ["b"])
        #expect(state.total == 4)
    }

    @Test func failedReloadSurfacesErrorMessage() async {
        let rec = Recorder()
        let state = makeState(recorder: rec) { _ in throw NamedError(message: "offline") }
        state.reload(); await settle(state)

        #expect(state.error == "offline")
        #expect(state.loading == false)
    }
}

struct NamedItem: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

/// Minimal mutable box usable from a @Sendable closure on the main actor (tests are serial).
final class Locked<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
