import Foundation

public enum TotalCountMode: Int, Sendable {
    case none = 0
    case exact = 1
}

/// Mirrors the web admin's Criteria; `toJSON()` emits only explicitly-set parts.
///
/// This is a reference type (like the Kotlin class) so that `getAssociation(_:)` can hand back a
/// nested `Criteria` the caller mutates in place.
public final class Criteria: @unchecked Sendable {
    private var page: Int?
    private var limit: Int?
    private var term: String?
    private var totalCountMode: TotalCountMode?
    private var ids: [String] = []
    private var filters: [JSONValue] = []
    private var sorts: [JSONValue] = []
    private var aggregations: [JSONValue] = []
    /// Insertion order preserved so emitted JSON is stable.
    private var associations: [(name: String, criteria: Criteria)] = []
    private var includes: [(alias: String, fields: [String])] = []

    public init() {}

    @discardableResult public func setPage(_ page: Int) -> Criteria { self.page = page; return self }
    @discardableResult public func setLimit(_ limit: Int) -> Criteria { self.limit = limit; return self }
    @discardableResult public func setTerm(_ term: String) -> Criteria { self.term = term; return self }
    @discardableResult public func setIds(_ ids: [String]) -> Criteria { self.ids = ids; return self }
    @discardableResult public func setTotalCountMode(_ mode: TotalCountMode) -> Criteria {
        totalCountMode = mode; return self
    }

    @discardableResult public func addFilter(_ filter: JSONValue) -> Criteria {
        filters.append(filter); return self
    }

    @discardableResult public func addSorting(_ field: String, _ order: String = "ASC") -> Criteria {
        sorts.append(Criteria.sort(field, order)); return self
    }

    @discardableResult public func addAggregation(_ aggregation: JSONValue) -> Criteria {
        aggregations.append(aggregation); return self
    }

    /// Dot paths expand into nested association criteria, e.g. "deliveries.shippingMethod".
    @discardableResult public func addAssociation(_ path: String) -> Criteria {
        _ = getAssociation(path); return self
    }

    @discardableResult public func getAssociation(_ path: String) -> Criteria {
        var current = self
        for part in path.split(separator: ".").map(String.init) {
            if let existing = current.associations.first(where: { $0.name == part })?.criteria {
                current = existing
            } else {
                let created = Criteria()
                current.associations.append((part, created))
                current = created
            }
        }
        return current
    }

    @discardableResult public func addIncludes(_ entityAlias: String, _ fields: [String]) -> Criteria {
        if let idx = includes.firstIndex(where: { $0.alias == entityAlias }) {
            includes[idx].fields += fields
        } else {
            includes.append((entityAlias, fields))
        }
        return self
    }

    public func toJSON() -> JSONValue {
        var out: [String: JSONValue] = [:]
        if let page { out["page"] = .int(page) }
        if let limit { out["limit"] = .int(limit) }
        if let term { out["term"] = .string(term) }
        if !ids.isEmpty { out["ids"] = .array(ids.map { .string($0) }) }
        if let totalCountMode { out["total-count-mode"] = .int(totalCountMode.rawValue) }
        if !filters.isEmpty { out["filter"] = .array(filters) }
        if !sorts.isEmpty { out["sort"] = .array(sorts) }
        if !associations.isEmpty {
            var assoc: [String: JSONValue] = [:]
            for (name, criteria) in associations { assoc[name] = criteria.toJSON() }
            out["associations"] = .object(assoc)
        }
        if !includes.isEmpty {
            var inc: [String: JSONValue] = [:]
            for (alias, fields) in includes { inc[alias] = .array(fields.map { .string($0) }) }
            out["includes"] = .object(inc)
        }
        if !aggregations.isEmpty { out["aggregations"] = .array(aggregations) }
        return .object(out)
    }

    // MARK: - Filter / sort / aggregation builders

    /// `value` accepts String, Int, Double, Bool, or nil (→ JSON null).
    private static func primitive(_ value: JSONValue?) -> JSONValue { value ?? .null }

    public static func equals(_ field: String, _ value: JSONValue?) -> JSONValue {
        .object(["type": "equals", "field": .string(field), "value": primitive(value)])
    }

    public static func equalsAny(_ field: String, _ values: [JSONValue]) -> JSONValue {
        .object(["type": "equalsAny", "field": .string(field), "value": .array(values)])
    }

    public static func contains(_ field: String, _ value: String) -> JSONValue {
        textFilter("contains", field, value)
    }

    public static func prefix(_ field: String, _ value: String) -> JSONValue {
        textFilter("prefix", field, value)
    }

    public static func suffix(_ field: String, _ value: String) -> JSONValue {
        textFilter("suffix", field, value)
    }

    private static func textFilter(_ type: String, _ field: String, _ value: String) -> JSONValue {
        .object(["type": .string(type), "field": .string(field), "value": .string(value)])
    }

    public static func range(
        _ field: String,
        gte: JSONValue? = nil,
        lte: JSONValue? = nil,
        gt: JSONValue? = nil,
        lt: JSONValue? = nil
    ) -> JSONValue {
        var params: [String: JSONValue] = [:]
        if let gte { params["gte"] = gte }
        if let lte { params["lte"] = lte }
        if let gt { params["gt"] = gt }
        if let lt { params["lt"] = lt }
        return .object(["type": "range", "field": .string(field), "parameters": .object(params)])
    }

    public static func not(_ op: String, _ filters: JSONValue...) -> JSONValue {
        compound("not", op, filters)
    }

    public static func multi(_ op: String, _ filters: JSONValue...) -> JSONValue {
        compound("multi", op, filters)
    }

    private static func compound(_ type: String, _ op: String, _ filters: [JSONValue]) -> JSONValue {
        .object(["type": .string(type), "operator": .string(op), "queries": .array(filters)])
    }

    public static func sort(_ field: String, _ order: String = "ASC") -> JSONValue {
        .object(["field": .string(field), "order": .string(order)])
    }

    public static func sum(_ name: String, _ field: String) -> JSONValue { metric("sum", name, field) }
    public static func avg(_ name: String, _ field: String) -> JSONValue { metric("avg", name, field) }
    public static func min(_ name: String, _ field: String) -> JSONValue { metric("min", name, field) }
    public static func max(_ name: String, _ field: String) -> JSONValue { metric("max", name, field) }
    public static func count(_ name: String, _ field: String) -> JSONValue { metric("count", name, field) }
    public static func stats(_ name: String, _ field: String) -> JSONValue { metric("stats", name, field) }

    private static func metric(_ type: String, _ name: String, _ field: String) -> JSONValue {
        .object(["name": .string(name), "type": .string(type), "field": .string(field)])
    }

    public static func terms(
        _ name: String,
        _ field: String,
        limit: Int? = nil,
        sort: JSONValue? = nil,
        aggregation: JSONValue? = nil
    ) -> JSONValue {
        var out: [String: JSONValue] = [
            "name": .string(name), "type": "terms", "field": .string(field),
        ]
        if let limit { out["limit"] = .int(limit) }
        if let sort { out["sort"] = sort }
        if let aggregation { out["aggregation"] = aggregation }
        return .object(out)
    }

    public static func histogram(
        _ name: String,
        _ field: String,
        interval: String,
        aggregation: JSONValue? = nil
    ) -> JSONValue {
        var out: [String: JSONValue] = [
            "name": .string(name), "type": "histogram", "field": .string(field),
            "interval": .string(interval),
        ]
        if let aggregation { out["aggregation"] = aggregation }
        return .object(out)
    }
}
