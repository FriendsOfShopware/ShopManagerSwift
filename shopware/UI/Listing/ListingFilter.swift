import Foundation
import ShopwareAdminAPI

struct FilterOption: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
}

/// Declarative per-listing filter config, mirroring the web admin's filterFactory. Each case maps
/// a `FilterValue` to one or more criteria filter objects via `criteria(for:)`.
enum ListingFilter: Identifiable, Sendable {
    enum TextMode: Sendable { case contains, equals, prefix }

    case text(key: String, label: String, field: String, mode: TextMode = .contains)
    case numberRange(key: String, label: String, field: String)
    case dateRange(key: String, label: String, field: String, withPresets: Bool = true)
    case options(
        key: String, label: String, field: String, multi: Bool = true,
        staticOptions: [FilterOption]? = nil,
        loadOptions: (@Sendable (ShopApi) async throws -> [FilterOption])? = nil
    )
    /// Boolean field as two static options ("true"/"false" ids); emits equals(field, Bool).
    case bool(key: String, label: String, field: String, trueLabel: String, falseLabel: String)
    /// `field` must already include ".id" where the existence check targets an association.
    case existence(key: String, label: String, field: String, hasLabel: String, hasNotLabel: String)

    var key: String {
        switch self {
        case let .text(key, _, _, _),
             let .numberRange(key, _, _),
             let .dateRange(key, _, _, _),
             let .options(key, _, _, _, _, _),
             let .bool(key, _, _, _, _),
             let .existence(key, _, _, _, _):
            return key
        }
    }

    var label: String {
        switch self {
        case let .text(_, label, _, _),
             let .numberRange(_, label, _),
             let .dateRange(_, label, _, _),
             let .options(_, label, _, _, _, _),
             let .bool(_, label, _, _, _),
             let .existence(_, label, _, _, _):
            return label
        }
    }

    var id: String { key }

    func criteria(for value: FilterValue) -> [JSONValue] {
        if value.isEmpty { return [] }
        switch (self, value) {
        case let (.text(_, _, field, mode), .text(text)):
            switch mode {
            case .contains: return [Criteria.contains(field, text)]
            case .equals: return [Criteria.equals(field, .string(text))]
            case .prefix: return [Criteria.prefix(field, text)]
            }

        case let (.numberRange(_, _, field), .range(min, max)):
            return [Criteria.range(field, gte: min.map { .number($0) }, lte: max.map { .number($0) })]

        case let (.dateRange(_, _, field, _), .dateRange(from, to)):
            return [Criteria.range(
                field,
                gte: from.map { .string(isoInstant(startOfDay($0))) },
                // exclusive next-day bound keeps the full "to" day incl. sub-second timestamps
                lt: to.map { .string(isoInstant(startOfDay(nextDay($0)))) }
            )]

        case let (.options(_, _, field, _, _, _), .options(ids)):
            return [Criteria.equalsAny(field, ids.sorted().map { .string($0) })]

        case let (.bool(_, _, field, _, _), .options(ids)):
            guard ids.count == 1, let only = ids.first else { return [] }
            return [Criteria.equals(field, .bool(only == "true"))]

        case let (.existence(_, _, field, _, _), .existence(has)):
            return [
                has == true
                    ? Criteria.not("and", Criteria.equals(field, nil))
                    : Criteria.equals(field, nil)
            ]

        default:
            return []
        }
    }
}

/// Shared across the Orders/Customers/Reviews/Promos listings. `field` is the entity's
/// salesChannelId FK; promotions use the m:n path "salesChannels.salesChannelId".
func salesChannelFilter(label: String, field: String = "salesChannelId") -> ListingFilter {
    .options(key: "salesChannel", label: label, field: field, loadOptions: { api in
        try await api.repository("sales-channel").search(
            Criteria()
                .setLimit(100)
                .addSorting("name")
                .addIncludes("sales_channel", ["id", "name", "translated"])
        ).data.compactMap { c in
            c.id.map { FilterOption(id: $0, label: c.translated("name") ?? "—") }
        }
    })
}

/// The current value of a filter. `.options` covers both Options and Bool filters.
enum FilterValue: Equatable, Sendable {
    case text(String)
    case range(min: Double?, max: Double?)
    case dateRange(from: Date?, to: Date?)
    case options(Set<String>)
    case existence(Bool?)

    var isEmpty: Bool {
        switch self {
        case let .text(text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .range(min, max): return min == nil && max == nil
        case let .dateRange(from, to): return from == nil && to == nil
        case let .options(ids): return ids.isEmpty
        case let .existence(has): return has == nil
        }
    }
}

// MARK: - Date helpers (local-day boundaries → UTC ISO strings)

private var localCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    return cal
}

private func startOfDay(_ date: Date) -> Date { localCalendar.startOfDay(for: date) }
private func nextDay(_ date: Date) -> Date { localCalendar.date(byAdding: .day, value: 1, to: date)! }
private func isoInstant(_ date: Date) -> String { date.ISO8601Format(.iso8601) }
