import Foundation

public enum ApiError: Error, Sendable {
    case network(message: String, underlying: String?)
    case auth(message: String)
    /// The stored refresh token was rejected (revoked/expired) — the user must sign in again.
    /// Thrown only by the token refresh path, never by ordinary 401 responses.
    case authExpired(message: String)
    case forbidden(message: String, missingPrivileges: [String])
    case notFound(message: String)
    case validation(violations: [Violation])
    case server(status: Int, message: String)
    case unexpected(status: Int, message: String)

    public struct Violation: Sendable, Equatable {
        public let code: String?
        public let title: String?
        public let detail: String?
        public let pointer: String?
    }

    public var message: String {
        switch self {
        case let .network(message, _): return message
        case let .auth(message): return message
        case let .authExpired(message): return message
        case let .forbidden(message, _): return message
        case let .notFound(message): return message
        case let .validation(violations):
            return violations.compactMap { $0.detail ?? $0.title }.first ?? "Validation failed"
        case let .server(_, message): return message
        case let .unexpected(_, message): return message
        }
    }

    static func networkError(_ error: Error) -> ApiError {
        .network(message: error.localizedDescription, underlying: String(describing: error))
    }

    public static func parse(status: Int, body: String?) -> ApiError {
        let root: JSONValue? = body.flatMap { JSONValue.parse($0) }
        let rootObject = root?.objectValue
        let errors: [[String: JSONValue]] = {
            guard case let .array(items)? = root?["errors"] else { return [] }
            return items.compactMap { $0.objectValue }
        }()

        let violations: [Violation] = errors.map { err in
            Violation(
                code: text(err, "code"),
                title: text(err, "title"),
                detail: text(err, "detail"),
                pointer: err["source"]?.objectValue.flatMap { text($0, "pointer") }
            )
        }

        let message = violations.compactMap { $0.detail ?? $0.title }.first
            ?? rootObject.flatMap { text($0, "error_description") }
            ?? rootObject.flatMap { text($0, "error") }
            ?? "HTTP \(status)"

        switch status {
        case 400 where !violations.isEmpty:
            return .validation(violations: violations)
        case 401:
            return .auth(message: message)
        case 403:
            // 6.7 serializes the 403 detail as a JSON blob; show its inner message instead.
            return .forbidden(
                message: forbiddenMessage(violations) ?? message,
                missingPrivileges: missingPrivileges(errors)
            )
        case 404:
            return .notFound(message: message)
        case 500...599:
            return .server(status: status, message: message)
        default:
            return .unexpected(status: status, message: message)
        }
    }

    private static func forbiddenMessage(_ violations: [Violation]) -> String? {
        for v in violations {
            if let detail = v.detail,
               let parsed = JSONValue.parse(detail)?.objectValue {
                return text(parsed, "message") ?? v.title
            }
        }
        return nil
    }

    private static func missingPrivileges(_ errors: [[String: JSONValue]]) -> [String] {
        for error in errors {
            if let privs = privileges(error["meta"]) { return privs }
            if let detail = text(error, "detail"),
               let privs = privileges(JSONValue.parse(detail)) { return privs }
        }
        return []
    }

    /// Accepts a plain array of privileges, or an object carrying them under
    /// "missingPrivileges" (directly or below "parameters", as 403 meta does).
    private static func privileges(_ element: JSONValue?) -> [String]? {
        switch element {
        case let .array(items)?:
            let result = items.compactMap { item -> String? in
                if item.isNull { return nil }
                return item.stringValue
            }
            return result.isEmpty ? nil : result
        case let .object(o)?:
            return privileges(o["missingPrivileges"]) ?? privileges(o["parameters"])
        default:
            return nil
        }
    }

    private static func text(_ object: [String: JSONValue], _ field: String) -> String? {
        guard let value = object[field], !value.isNull, let s = value.stringValue else { return nil }
        return s.isEmpty ? nil : s
    }
}
