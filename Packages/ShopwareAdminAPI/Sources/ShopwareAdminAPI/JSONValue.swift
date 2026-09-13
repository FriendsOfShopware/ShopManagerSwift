import Foundation
import CoreFoundation

/// A self-describing JSON value, the Swift analogue of kotlinx.serialization's `JsonElement`.
///
/// The Admin API client builds request bodies (`Criteria`) and reads responses (`SwEntity`)
/// through this type so that JSON shapes — which are a server contract — stay explicit and
/// `null`-safe. `.null` is a real, distinguishable case (Shopware sends `null` fields that must
/// count as *absent*, never as an empty string).
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// All numbers are kept as `Double`; `intValue`/`longValue` re-derive integers on read.
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Convenience constructors

    public static func int(_ value: Int) -> JSONValue { .number(Double(value)) }

    // MARK: Typed reads (JsonNull counts as absent)

    public var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }

    public var doubleValue: Double? {
        if case let .number(n) = self { return n }
        return nil
    }

    public var intValue: Int? {
        guard case let .number(n) = self else { return nil }
        return Int(n)
    }

    public var int64Value: Int64? {
        guard case let .number(n) = self else { return nil }
        return Int64(n)
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(o) = self else { return nil }
        return o[key]
    }
}

// MARK: - Parsing & serialization

extension JSONValue {
    /// Parses raw JSON text. Returns nil on malformed input (mirrors `runCatching { … }.getOrNull()`).
    public static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> JSONValue? {
        guard let obj = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) else { return nil }
        return JSONValue(foundation: obj)
    }

    init(foundation object: Any) {
        switch object {
        case is NSNull:
            self = .null
        case let n as NSNumber:
            // Distinguish Bool from numeric: CFBoolean reports as the Bool object type.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let s as String:
            self = .string(s)
        case let a as [Any]:
            self = .array(a.map { JSONValue(foundation: $0) })
        case let d as [String: Any]:
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(d.count)
            for (k, v) in d { out[k] = JSONValue(foundation: v) }
            self = .object(out)
        default:
            self = .null
        }
    }

    /// Converts back to a Foundation object suitable for `JSONSerialization`.
    var foundationValue: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(b): return b
        case let .number(n):
            // Emit whole doubles as integers so request bodies read 1 not 1.0
            // (matches the JsonPrimitive(Int) / JsonPrimitive(Double) split server-side).
            if n.rounded() == n, abs(n) < 9.007199254740992e15 {
                return Int64(n)
            }
            return n
        case let .string(s): return s
        case let .array(a): return a.map { $0.foundationValue }
        case let .object(o):
            var out: [String: Any] = [:]
            for (k, v) in o { out[k] = v.foundationValue }
            return out
        }
    }

    /// Serializes to compact JSON text. `sortedKeys` makes output deterministic for tests.
    public func encoded(sortedKeys: Bool = false) -> Data {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if sortedKeys { options.insert(.sortedKeys) }
        return (try? JSONSerialization.data(withJSONObject: foundationValue, options: options))
            ?? Data("null".utf8)
    }
}

// MARK: - Ergonomic literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
