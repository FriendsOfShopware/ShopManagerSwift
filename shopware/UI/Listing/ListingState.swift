import Foundation
import Observation
import ShopwareAdminAPI

/// Generic paged listing holder: term + declarative filters + load-more, shared by screen view
/// models. `@MainActor @Observable` so SwiftUI lists observe `items`/`loading`/`error` directly.
@MainActor
@Observable
final class ListingState<T> {
    let filters: [ListingFilter]

    private(set) var items: [T] = []
    private(set) var total = 0
    private(set) var loading = false
    private(set) var error: String?
    private(set) var term = ""
    private(set) var activeValues: [String: FilterValue] = [:]

    var activeFilterCount: Int { activeValues.count }

    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let source: (Criteria) async throws -> SearchResult
    @ObservationIgnored private let baseCriteria: () -> Criteria
    @ObservationIgnored private let mapper: (SwEntity) -> T
    @ObservationIgnored private let errorFallback: String

    @ObservationIgnored private var page = 1
    @ObservationIgnored private(set) var fetchTask: Task<Void, Never>?
    /// Guards against out-of-order completions (reload during load-more, rapid filter taps).
    @ObservationIgnored private var fetchId = 0

    init(
        pageSize: Int = 25,
        filters: [ListingFilter] = [],
        source: @escaping (Criteria) async throws -> SearchResult,
        baseCriteria: @escaping () -> Criteria,
        mapper: @escaping (SwEntity) -> T,
        errorFallback: String = "Request failed"
    ) {
        self.pageSize = pageSize
        self.filters = filters
        self.source = source
        self.baseCriteria = baseCriteria
        self.mapper = mapper
        self.errorFallback = errorFallback
    }

    func reload() {
        page = 1
        fetchTask?.cancel()
        fetchTask = Task { await fetch(replace: true) }
    }

    func loadMore() {
        if loading || items.count >= total { return }
        page += 1
        fetchTask = Task { await fetch(replace: false) }
    }

    func setTerm(_ t: String) { term = t }

    func search() { reload() }

    func setFilterValue(_ key: String, _ value: FilterValue?) {
        if let value, !value.isEmpty {
            activeValues[key] = value
        } else {
            activeValues.removeValue(forKey: key)
        }
        reload()
    }

    func applyFilterValues(_ values: [String: FilterValue]) {
        activeValues = values.filter { !$0.value.isEmpty }
        reload()
    }

    func mutateItem(where predicate: (T) -> Bool, transform: (T) -> T) {
        items = items.map { predicate($0) ? transform($0) : $0 }
    }

    func removeItem(where predicate: (T) -> Bool) {
        let remaining = items.filter { !predicate($0) }
        total -= items.count - remaining.count
        items = remaining
    }

    private func fetch(replace: Bool) async {
        fetchId += 1
        let id = fetchId
        loading = true
        error = nil
        do {
            let result = try await source(buildCriteria())
            if id != fetchId { return }
            total = result.total
            let mapped = result.data.map(mapper)
            items = replace ? mapped : items + mapped
        } catch is CancellationError {
            return
        } catch {
            if id != fetchId { return }
            if !replace { page -= 1 }
            self.error = (error as? ApiError)?.message
                ?? (error as? LocalizedError)?.errorDescription
                ?? errorFallback
        }
        if id == fetchId { loading = false }
    }

    private func buildCriteria() -> Criteria {
        let criteria = baseCriteria()
            .setPage(page)
            .setLimit(pageSize)
            .setTotalCountMode(.exact)
        if !term.trimmingCharacters(in: .whitespaces).isEmpty { criteria.setTerm(term) }
        // Emit in declared-filter order (not activeValues dict order) so the criteria is stable.
        for filter in filters {
            guard let value = activeValues[filter.key] else { continue }
            for f in filter.criteria(for: value) { criteria.addFilter(f) }
        }
        return criteria
    }
}
