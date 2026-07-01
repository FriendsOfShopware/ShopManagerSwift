import SwiftUI
import Observation
import ShopwareAdminAPI

/// Editable draft state for the filter sheet: the in-progress `[key: FilterValue]` plus async-loaded
/// options. Owning this in an `@Observable` keeps the binding plumbing (and its `FilterValue`
/// packing/unpacking) out of the view body and makes it testable — the view just consumes the
/// binding factories below.
@MainActor
@Observable
final class FilterDraft {
    private(set) var values: [String: FilterValue] = [:]
    /// Async-loaded options per filter key (sales channel, manufacturer, …).
    private(set) var loadedOptions: [String: [FilterOption]] = [:]

    /// Seed from the listing's current active filters.
    func seed(_ active: [String: FilterValue]) { values = active }

    var isEmpty: Bool { values.allSatisfy(\.value.isEmpty) }

    func clear() { values = [:] }

    /// Options for an `.options` filter — its own async-loaded set, or static options.
    func options(for filter: ListingFilter) -> [FilterOption] {
        if case let .options(key, _, _, _, staticOptions, _) = filter {
            return staticOptions ?? loadedOptions[key] ?? []
        }
        return []
    }

    /// Loads every async `.options` filter's choices once.
    func loadOptions(for filters: [ListingFilter], api: ShopApi?) async {
        guard let api else { return }
        for filter in filters {
            if case let .options(key, _, _, _, staticOptions, loadOptions) = filter,
               staticOptions == nil, let loadOptions, loadedOptions[key] == nil,
               let result = try? await loadOptions(api) {
                loadedOptions[key] = result
            }
        }
    }

    // MARK: - Binding factories (kept out of the view body; each maps one FilterValue case)

    func textBinding(_ key: String) -> Binding<String> {
        Binding(get: { if case let .text(t)? = self.values[key] { t } else { "" } },
                set: { self.values[key] = .text($0) })
    }

    func rangeBinding(_ key: String) -> Binding<ClosedRangeValue> {
        Binding(
            get: {
                if case let .range(lo, hi)? = self.values[key] { ClosedRangeValue(min: lo, max: hi) }
                else { ClosedRangeValue(min: nil, max: nil) }
            },
            set: { self.values[key] = .range(min: $0.min, max: $0.max) }
        )
    }

    func dateBinding(_ key: String) -> Binding<DateRangeValue> {
        Binding(
            get: {
                if case let .dateRange(f, t)? = self.values[key] { DateRangeValue(from: f, to: t) }
                else { DateRangeValue(from: nil, to: nil) }
            },
            set: { self.values[key] = .dateRange(from: $0.from, to: $0.to) }
        )
    }

    func optionsBinding(_ key: String) -> Binding<Set<String>> {
        Binding(get: { if case let .options(ids)? = self.values[key] { ids } else { [] } },
                set: { self.values[key] = .options($0) })
    }

    /// Bool filters store a single "true"/"false" id in an options set; surface it as an optional.
    func boolBinding(_ key: String) -> Binding<String?> {
        Binding(get: { if case let .options(ids)? = self.values[key] { ids.first } else { nil } },
                set: { self.values[key] = .options($0.map { [$0] } ?? []) })
    }

    func existenceBinding(_ key: String) -> Binding<Bool?> {
        Binding(get: { if case let .existence(has)? = self.values[key] { has } else { nil } },
                set: { self.values[key] = .existence($0) })
    }
}

/// Value carriers so the range/date editors bind to a single struct with named members.
struct ClosedRangeValue: Equatable { var min: Double?; var max: Double? }
struct DateRangeValue: Equatable { var from: Date?; var to: Date? }
