#if DEBUG
import Foundation
import ShopwareAdminAPI

/// Offline API contract fixture: unknown routes, mutations and filters fail explicitly.
actor ReviewUITestTransport: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    private(set) var reviews: [JSONValue]
    private var failures: Set<String>
    private let privileges: [String]
    init(arguments: [String] = [], count: Int = 3) {
        failures = Set(arguments)
        var allowed = ["product_review:read", "custom_field_set:read", "custom_field:read", "language:read"]
        if !arguments.contains("--read-only") {
            allowed += ["product:read", "customer:read", "product_review:update", "product_review:delete"]
        }
        if arguments.contains("--editor-only") { allowed.removeAll { $0 == "product_review:delete" } }
        if arguments.contains("--deleter-only") { allowed.removeAll { $0 == "product_review:update" } }
        privileges = allowed
        reviews = arguments.contains("--empty-reviews") ? [] : (0..<count).map(Self.review)
    }
    func inject(_ flag: String) { failures.insert(flag) }
    static let languages: [JSONValue] = [.object(["id": "en", "name": "English"]), .object(["id": "de", "name": "Deutsch"])]
    static func review(_ index: Int) -> JSONValue {
        let titles = ["Beautiful quality and a perfect fit", "Thoughtful packaging, lovely gift", "Color differs from the photos"]
        return .object([
            "id": .string("review-\(index)"), "title": .string(titles[index % 3]),
            "content": "The linen feels soft and the stitching is excellent. I wore it throughout a warm weekend and it stayed comfortable. The size guide was accurate; I would happily order another color.",
            "points": .number(index % 3 == 0 ? 4.5 : index % 3 == 1 ? 5 : 2), "status": .bool(index % 3 == 1),
            "comment": index % 3 == 1 ? "Thank you for sharing your experience. We hope you enjoy your gift!" : "",
            "customerId": index % 3 == 2 ? .null : "customer", "externalUser": "Guest reviewer", "externalEmail": "guest@example.test",
            "customer": index % 3 == 2 ? .null : .object(["id": "customer", "firstName": "Alexandra", "lastName": "Montgomery", "email": "alexandra@example.test"]),
            "productId": "product", "product": .object(["id": "product", "name": "Linen shirt · Sand", "translated": .object(["name": "Linen shirt · Sand"])]),
            "salesChannelId": "channel", "salesChannel": .object(["id": "channel", "name": "Storefront"]),
            "languageId": "en", "language": languages[0], "createdAt": .string(String(format: "2026-09-%02dT10:30:00.000+00:00", 11 - index % 10)),
            "customFields": .object(["review_reference": "REF-42", "unexposed": "preserved"])
        ])
    }
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "review-ui.test" else { throw unsupported(request.url) }
        let path = url.path, payload = request.body.flatMap(JSONValue.parse) ?? .object([:])
        if path == "/api/oauth/token" { return response(.object(["access_token": "fixture", "expires_in": 3600])) }
        requests.append(request)
        if path == "/api/_info/me" {
            try fail("--fail-permissions-once")
            return response(.object(["data": .object(["id": "user", "admin": false, "aclRoles": .array([.object(["privileges": .array(privileges.map(JSONValue.string))])])])]))
        }
        if path.hasPrefix("/api/search/"), request.method == .post {
            let entity = url.lastPathComponent
            var rows: [JSONValue]
            switch entity {
            case "product-review":
                try fail(payload["ids"] == nil ? "--fail-list-once" : "--fail-detail-once")
                rows = reviews
            case "language": rows = Self.languages
            case "sales-channel": rows = [.object(["id": "channel", "name": "Storefront"])]
            case "customer": rows = [.object(["id": "customer", "firstName": "Alexandra", "lastName": "Montgomery", "email": "alexandra@example.test"])]
            case "product": rows = [.object(["id": "product", "name": "Linen shirt · Sand"])]
            case "custom-field-set":
                try fail("--fail-fields-once")
                rows = [.object(["id": "review-fields", "name": "review_fields", "active": true, "config": .object(["label": .object(["en-GB": "Additional information", "de-DE": "Zusätzliche Informationen"])]),
                                 "customFields": .array([.object(["id": "field", "name": "review_reference", "type": "text", "active": true,
                                                                 "config": .object(["label": .object(["en-GB": "Reference", "de-DE": "Referenz"]), "componentName": "sw-text-field"])])])])]
            default: throw unsupported(path)
            }
            if let ids = payload["ids"]?.arrayValue { rows = rows.filter { ids.contains($0["id"] ?? .null) } }
            if entity != "custom-field-set" {
                for filter in payload["filter"]?.arrayValue ?? [] { rows = try rows.filter { try matches($0, filter) } }
            }
            if let term = payload["term"]?.stringValue, !term.isEmpty { rows = rows.filter { String(decoding: $0.encoded(), as: UTF8.self).localizedCaseInsensitiveContains(term) } }
            rows.sort { a, b in
                for sort in payload["sort"]?.arrayValue ?? [] {
                    let key = sort["field"]?.stringValue ?? "id", lhs = value(a, key), rhs = value(b, key)
                    let comparison: ComparisonResult
                    if let left = lhs?.doubleValue, let right = rhs?.doubleValue { comparison = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending }
                    else { comparison = sortValue(lhs).compare(sortValue(rhs), options: [.numeric, .caseInsensitive]) }
                    if comparison != .orderedSame { return sort["order"] == "DESC" ? comparison == .orderedDescending : comparison == .orderedAscending }
                }
                return false
            }
            let total = rows.count, limit = payload["limit"]?.intValue ?? 25, page = payload["page"]?.intValue ?? 1
            return response(.object(["total": .int(total), "data": .array(Array(rows.dropFirst(max(page - 1, 0) * limit).prefix(limit)))]))
        }
        if path.hasPrefix("/api/product-review/") {
            let id = url.lastPathComponent
            guard let index = reviews.firstIndex(where: { $0["id"]?.stringValue == id }) else { throw ApiError.notFound(message: "Review not found") }
            if request.method == .delete {
                guard privileges.contains("product_review:delete") else { throw ApiError.unexpected(status: 403, message: "Read only") }
                try fail("--fail-delete-\(id)-once")
                reviews.remove(at: index)
                return HTTPResponse(status: 204, body: Data())
            }
            if request.method == .patch {
                guard privileges.contains("product_review:update") else { throw ApiError.unexpected(status: 403, message: "Read only") }
                try fail("--fail-save-once")
                let patch = payload.objectValue ?? [:]
                guard Set(patch.keys).isSubset(of: ["status", "languageId", "comment", "customFields"]) else { throw unsupported("Unexpected review patch") }
                if let language = patch["languageId"], !Self.languages.contains(where: { $0["id"] == language }) { throw ApiError.unexpected(status: 400, message: "Language is required") }
                var row = reviews[index].objectValue!
                for (key, value) in patch { row[key] = value }
                if let id = patch["languageId"] { row["language"] = Self.languages.first { $0["id"] == id } }
                reviews[index] = .object(row)
                return HTTPResponse(status: 204, body: Data())
            }
        }
        throw unsupported(path)
    }
    private func sortValue(_ value: JSONValue?) -> String { value?.boolValue.map { $0 ? "1" : "0" } ?? value?.stringValue ?? "" }
    private func value(_ row: JSONValue, _ field: String) -> JSONValue? { field.split(separator: ".").reduce(Optional(row)) { $0?[String($1)] } }
    private func matches(_ row: JSONValue, _ filter: JSONValue) throws -> Bool {
        let actual = value(row, filter["field"]?.stringValue ?? "") ?? .null
        switch filter["type"]?.stringValue {
        case "equals": return actual == (filter["value"] ?? .null)
        case "equalsAny": return filter["value"]?.arrayValue?.contains(actual) ?? false
        case "range":
            guard let number = actual.doubleValue else { return false }
            let bounds = filter["parameters"]
            return (bounds?["gte"]?.doubleValue.map { number >= $0 } ?? true) && (bounds?["lte"]?.doubleValue.map { number <= $0 } ?? true)
        default: throw unsupported("Unknown review filter: \(filter)")
        }
    }
    private func fail(_ flag: String) throws { if failures.remove(flag) != nil { throw ApiError.unexpected(status: 422, message: "Fixture request failed. Please retry.") } }
    private func unsupported(_ path: String) -> ApiError { .unexpected(status: 500, message: "Unsupported review fixture route: \(path)") }
    private func response(_ body: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: body.encoded()) }
}
#endif
