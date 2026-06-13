import Foundation

/// Null-safe view over a plain-JSON Admin API entity; JSON `null` counts as absent everywhere.
public struct SwEntity: Sendable {
    public let json: JSONValue

    public init(_ json: JSONValue) { self.json = json }

    public var id: String? { string("id") }

    public func string(_ field: String) -> String? { primitive(field)?.stringValue }
    public func int(_ field: String) -> Int? { primitive(field)?.intValue }
    public func long(_ field: String) -> Int64? { primitive(field)?.int64Value }
    public func double(_ field: String) -> Double? { primitive(field)?.doubleValue }
    public func boolean(_ field: String) -> Bool? { primitive(field)?.boolValue }

    /// Accepts "2026-06-11T08:21:33.000+00:00", "2026-06-11 08:21:33.000" (UTC),
    /// and date-only "2026-06-11" prefixes (midnight UTC).
    public func date(_ field: String) -> Date? {
        guard let value = string(field) else { return nil }
        return SwDate.parse(value)
    }

    /// "translated" is `[]` instead of `{}` when an entity has no translatable fields.
    public func translated(_ field: String) -> String? {
        if case let .object(translated)? = json["translated"],
           let resolved = translated[field], !resolved.isNull,
           let s = resolved.stringValue {
            return s
        }
        return string(field)
    }

    public func entity(_ field: String) -> SwEntity? {
        if case .object? = json[field] { return SwEntity(json[field]!) }
        return nil
    }

    public func entities(_ field: String) -> [SwEntity] {
        guard case let .array(items)? = json[field] else { return [] }
        return items.compactMap { value in
            if case .object = value { return SwEntity(value) }
            return nil
        }
    }

    private func primitive(_ field: String) -> JSONValue? {
        guard let v = json[field], !v.isNull else { return nil }
        switch v {
        case .array, .object: return nil
        default: return v
        }
    }
}

/// Date parsing for the three formats Shopware emits.
///
/// Uses the value-type `Date.ISO8601FormatStyle` (Sendable) rather than the reference-type
/// `ISO8601DateFormatter`, so the parsers can be `static let` under Swift 6 strict concurrency.
enum SwDate {
    private static let utc = TimeZone(identifier: "UTC")!

    // Internet date-time forms, with and without fractional seconds. The parsers require a
    // timezone designator, so bare "space" datetimes are normalized to "…TZ" before parsing.
    private static let iso = Date.ISO8601FormatStyle(timeZone: utc)
    private static let isoFractional = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true, timeZone: utc
    )

    static func parse(_ value: String) -> Date? {
        // Offset form: "2026-06-11T08:21:33.000+00:00".
        if let d = try? isoFractional.parse(value) { return d }
        if let d = try? iso.parse(value) { return d }

        // Space-separated UTC: "2026-06-11 08:21:33[.SSS]" → append a Z and retry.
        if value.contains(" ") {
            let normalized = value.replacingOccurrences(of: " ", with: "T") + "Z"
            if let d = try? isoFractional.parse(normalized) { return d }
            if let d = try? iso.parse(normalized) { return d }
        }

        // Date-only prefix: "2026-06-11" → midnight UTC.
        if value.count >= 10 {
            let midnight = String(value.prefix(10)) + "T00:00:00Z"
            if let d = try? iso.parse(midnight) { return d }
        }
        return nil
    }
}

/// One bucket of a bucketing aggregation (terms/histogram).
public struct Bucket: Sendable {
    public let entity: SwEntity
    public let key: String
    public let count: Int

    public init(_ entity: SwEntity) {
        self.entity = entity
        self.key = entity.string("key") ?? ""
        self.count = entity.int("count") ?? 0
    }

    /// Without a name, takes the first child object carrying a "sum" key (nested metric aggregation).
    public func sum(_ nestedName: String? = nil) -> Double {
        let holder: JSONValue?
        if let nestedName {
            holder = entity.json[nestedName]
        } else {
            if case let .object(fields) = entity.json {
                holder = fields.values.first { value in
                    if case let .object(o) = value { return o["sum"] != nil }
                    return false
                }
            } else {
                holder = nil
            }
        }
        if case let .object(o)? = holder, let sum = o["sum"]?.doubleValue { return sum }
        return 0.0
    }

    /// Buckets of a nested bucketing aggregation (terms→histogram, terms→terms, …).
    public func buckets(_ name: String) -> [Bucket] {
        guard case let .object(o)? = entity.json[name],
              case let .array(items)? = o["buckets"] else { return [] }
        return items.compactMap { value in
            if case .object = value { return Bucket(SwEntity(value)) }
            return nil
        }
    }
}

public struct SearchResult: Sendable {
    public let total: Int
    public let data: [SwEntity]
    public let aggregations: JSONValue

    public init(total: Int, data: [SwEntity], aggregations: JSONValue) {
        self.total = total
        self.data = data
        self.aggregations = aggregations
    }

    public func sum(_ name: String) -> Double {
        if case let .object(o)? = aggregations[name], let sum = o["sum"]?.doubleValue { return sum }
        return 0.0
    }

    public func count(_ name: String) -> Int {
        if case let .object(o)? = aggregations[name], let count = o["count"]?.intValue { return count }
        return 0
    }

    public func buckets(_ name: String) -> [Bucket] {
        guard case let .object(o)? = aggregations[name],
              case let .array(items)? = o["buckets"] else { return [] }
        return items.compactMap { value in
            if case .object = value { return Bucket(SwEntity(value)) }
            return nil
        }
    }

    public static func from(_ envelope: JSONValue) -> SearchResult {
        let total = envelope["total"]?.intValue ?? 0
        let data: [SwEntity]
        if case let .array(items)? = envelope["data"] {
            data = items.compactMap { value in
                if case .object = value { return SwEntity(value) }
                return nil
            }
        } else {
            data = []
        }
        let aggregations: JSONValue
        if case .object? = envelope["aggregations"] {
            aggregations = envelope["aggregations"]!
        } else {
            aggregations = .object([:])
        }
        return SearchResult(total: total, data: data, aggregations: aggregations)
    }
}
