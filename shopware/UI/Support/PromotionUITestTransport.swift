#if DEBUG
import Foundation
import ShopwareAdminAPI

/// Offline promotion API fixture. Unknown routes, filters and mutations fail explicitly.
actor PromotionUITestTransport: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    private(set) var promotions: [JSONValue]
    private(set) var codes: [JSONValue]
    private var failures: Set<String>
    private let privileges: [String]
    init(arguments: [String] = [], count: Int = 3) {
        failures = Set(arguments)
        var allowed = ["promotion:read", "promotion_individual_code:read", "promotion_discount:read", "custom_field_set:read", "custom_field:read", "rule:read", "sales_channel:read", "currency:read"]
        if !arguments.contains("--read-only") {
            allowed += ["promotion:create", "promotion:update", "promotion:delete", "promotion_individual_code:create", "promotion_discount:create", "promotion_discount:update", "promotion_discount:delete"]
            for entity in ["promotion_sales_channel", "promotion_persona_rule", "promotion_cart_rule", "promotion_order_rule"] { allowed += [entity + ":create", entity + ":delete"] }
        }
        if arguments.contains("--editor-only") { allowed.removeAll { $0 == "promotion:delete" || $0 == "promotion:create" } }
        if arguments.contains("--deleter-only") { allowed.removeAll { $0 == "promotion:update" || $0 == "promotion:create" } }
        privileges = allowed
        promotions = arguments.contains("--empty-promotions") ? [] : (0..<count).map(Self.promotion)
        if arguments.contains("--unassigned-promotion"), !promotions.isEmpty {
            var promotion = promotions[0].objectValue!
            promotion["salesChannels"] = .array([])
            promotions[0] = .object(promotion)
        }
        codes = (0..<30).map { Self.code($0) }
    }
    func inject(_ flag: String) { failures.insert(flag) }
    static let channels: [JSONValue] = [.object(["id": "channel", "name": "Storefront"]), .object(["id": "channel-2", "name": "Outlet"])]
    static let rules: [JSONValue] = [.object(["id": "rule", "name": "Customers with an account", "conditions": .array([.object(["id": "condition", "type": "customerLoggedIn"])])]),
        .object(["id": "restricted-rule", "name": "Cart total with discounts", "conditions": .array([.object(["id": "condition-2", "type": "cartCartAmount"])])])]
    static func promotion(_ index: Int) -> JSONValue {
        .object([
            "id": .string("promotion-\(index)"), "name": .string(["Summer essentials", "Welcome back", "Winter preview"][index % 3]),
            "active": .bool(index % 3 != 2), "priority": .int(index + 1), "orderCount": .int(index % 3 == 1 ? 14 : 0),
            "validFrom": .null, "validUntil": .null, "createdAt": "2026-09-01T10:00:00.000+00:00",
            "maxRedemptionsGlobal": .int(500), "maxRedemptionsPerCustomer": .int(1),
            "useCodes": .bool(index % 3 != 2), "useIndividualCodes": .bool(index % 3 == 0), "code": index % 3 == 1 ? "WELCOME15" : .null,
            "individualCodePattern": "SUMMER-%s%d%s%d%s%d", "preventCombination": false, "exclusionIds": .array([]),
            "useSetGroups": false, "customerRestriction": false,
            "salesChannels": .array([.object(["id": .string("mapping-\(index)"), "salesChannelId": "channel", "priority": .int(7), "salesChannel": channels[0]])]),
            "personaRules": .array([]), "cartRules": .array([]), "orderRules": .array([]), "personaCustomers": .array([]), "setgroups": .array([]),
            "discounts": index % 3 == 2 ? .array([]) : .array([.object(["id": .string("discount-\(index)"), "promotionId": .string("promotion-\(index)"), "type": "percentage", "scope": "cart", "value": .number(25.5), "maxValue": .number(100), "considerAdvancedRules": false, "sorterKey": "PRICE_ASC", "applierKey": "ALL", "usageKey": "ALL", "discountRules": .array([]), "promotionDiscountPrices": .array([])])]),
            "customFields": .object(["promotion_reference": "SUMMER-26", "unexposed": "preserved"])
        ])
    }
    static func code(_ index: Int) -> JSONValue {
        .object(["id": .string("code-\(index)"), "promotionId": "promotion-0", "code": .string(String(format: "SUMMER-A%03d", index)),
                 "payload": index == 0 ? .object(["customerId": "customer", "customerName": "Alexandra Montgomery"]) : .null,
                 "createdAt": "2026-09-01T10:00:00.000+00:00"])
    }
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "promotion-ui.test" else { throw unsupported(request.url) }
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
            case "promotion":
                try fail(payload["ids"] == nil ? "--fail-list-once" : "--fail-detail-once")
                rows = promotions
            case "promotion-individual-code": try fail("--fail-codes-once"); rows = codes
            case "sales-channel": rows = Self.channels
            case "rule": rows = Self.rules
            case "currency":
                try fail("--fail-currency-once")
                rows = [.object(["id": .string(PromotionActions.systemCurrencyID), "isoCode": failures.contains("--usd-currency") ? "USD" : "EUR", "isSystemDefault": true])]
            case "custom-field-set":
                try fail("--fail-fields-once")
                rows = [.object(["id": "promotion-fields", "name": "promotion_fields", "active": true, "config": .object(["label": .object(["en-GB": "Additional information", "de-DE": "Zusätzliche Informationen"])]),
                    "customFields": .array([.object(["id": "field", "name": "promotion_reference", "type": "text", "active": true, "config": .object(["label": .object(["en-GB": "Reference", "de-DE": "Referenz"]), "componentName": "sw-text-field"])])])])]
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

        if path == "/api/_action/promotion/codes/add-individual", request.method == .post {
            try require("promotion:update"); try require("promotion_individual_code:create"); try fail("--fail-generate-once")
            guard payload["promotionId"] == "promotion-0", let amount = payload["amount"]?.intValue, (1...500).contains(amount) else { throw unsupported("Invalid generation payload") }
            let start = codes.count; codes += (start..<(start + amount)).map(Self.code)
            return response(.object([:]))
        }
        if path == "/api/_action/sync", request.method == .post {
            try require("promotion:update"); try fail("--fail-conditions-once")
            guard request.headers["single-operation"] == "1", let operations = payload.objectValue,
                  let patch = operations["save-promotion"]?["payload"]?.arrayValue?.first,
                  let index = promotions.firstIndex(where: { $0["id"] == patch["id"] }) else { throw unsupported("Invalid conditions transaction") }
            for operation in operations.values {
                guard let entity = operation["entity"]?.stringValue, let action = operation["action"]?.stringValue,
                      action == "delete" || (entity == "promotion" && action == "upsert") else { throw unsupported("Invalid sync operation") }
                if action == "delete" { try require(entity + ":delete") }
            }
            var row = promotions[index].objectValue!
            let existingChannels = row["salesChannels"]?.arrayValue ?? []
            var channels: [JSONValue] = []
            for item in patch["salesChannels"]?.arrayValue ?? [] {
                let existing = existingChannels.first { $0["id"] == item["id"] }
                var channel = existing?.objectValue ?? [:]
                channel.merge(item.objectValue ?? [:]) { _, new in new }
                // Core requires priority when inserting a promotion_sales_channel.
                // Validate before applying any part of the atomic transaction.
                guard channel["id"]?.stringValue != nil, channel["salesChannelId"]?.stringValue != nil,
                      channel["priority"]?.intValue != nil else {
                    throw ApiError.unexpected(status: 400, message: "This value should not be blank.")
                }
                if existing == nil { try require("promotion_sales_channel:create") }
                channel["salesChannel"] = Self.channels.first { $0["id"] == channel["salesChannelId"] }
                channels.append(.object(channel))
            }
            for (key, value) in patch.objectValue ?? [:] { row[key] = value }
            row["salesChannels"] = .array(channels)
            for key in ["personaRules", "cartRules", "orderRules"] {
                row[key] = .array((patch[key]?.arrayValue ?? []).compactMap { item in Self.rules.first { $0["id"] == item["id"] } })
            }
            promotions[index] = .object(row)
            return response(.object([:]))
        }
        if path == "/api/promotion", request.method == .post {
            try require("promotion:create"); try fail("--fail-save-once")
            guard let id = payload["id"], !promotions.contains(where: { $0["id"] == id }) else { throw unsupported("Duplicate promotion") }
            var row = Self.promotion(2).objectValue!; row.merge(payload.objectValue!) { _, new in new }; promotions.append(.object(row))
            return HTTPResponse(status: 204, body: Data())
        }
        if path.hasPrefix("/api/promotion/"), let index = promotions.firstIndex(where: { $0["id"]?.stringValue == url.lastPathComponent }) {
            if request.method == .delete {
                try require("promotion:delete"); try fail("--fail-delete-\(url.lastPathComponent)-once")
                guard promotions[index]["orderCount"]?.intValue == 0 else { throw unsupported("Cannot delete redeemed promotion") }
                promotions.remove(at: index); return HTTPResponse(status: 204, body: Data())
            }
            if request.method == .patch {
                try require("promotion:update"); try fail("--fail-save-once")
                // Keep the fixture's API contract independent of the UI draft.
                let allowed: Set<String> = ["name", "active", "priority", "validFrom", "validUntil",
                    "maxRedemptionsGlobal", "maxRedemptionsPerCustomer", "useCodes", "useIndividualCodes",
                    "code", "individualCodePattern", "customFields"]
                guard Set(payload.objectValue!.keys).isSubset(of: allowed) else { throw unsupported("Unexpected promotion patch") }
                var row = promotions[index].objectValue!; row.merge(payload.objectValue!) { _, new in new }; promotions[index] = .object(row)
                return HTTPResponse(status: 204, body: Data())
            }
        }
        if path == "/api/promotion-discount" || path.hasPrefix("/api/promotion-discount/") {
            try require("promotion:update")
            let creating = request.method == .post, deleting = request.method == .delete
            try require("promotion_discount:" + (creating ? "create" : deleting ? "delete" : "update")); try fail("--fail-discount-once")
            let id = creating ? payload["id"]?.stringValue : url.lastPathComponent
            guard let index = promotions.firstIndex(where: { row in creating ? row["id"] == payload["promotionId"] : (row["discounts"]?.arrayValue ?? []).contains { $0["id"]?.stringValue == id } }), promotions[index]["orderCount"]?.intValue == 0 else { throw unsupported("Invalid discount mutation") }
            var row = promotions[index].objectValue!, discounts = row["discounts"]?.arrayValue ?? []
            if creating { discounts.append(payload) }
            else if deleting { discounts.removeAll { $0["id"]?.stringValue == id } }
            else {
                guard Set(payload.objectValue!.keys).isSubset(of: ["value", "maxValue"]), let index = discounts.firstIndex(where: { $0["id"]?.stringValue == id }) else { throw unsupported("Unexpected discount patch") }
                var discount = discounts[index].objectValue!; discount.merge(payload.objectValue!) { _, new in new }; discounts[index] = .object(discount)
            }
            row["discounts"] = .array(discounts); promotions[index] = .object(row)
            return HTTPResponse(status: 204, body: Data())
        }
        throw unsupported(path)
    }
    private func require(_ privilege: String) throws { if !privileges.contains(privilege) { throw ApiError.unexpected(status: 403, message: "Read only") } }
    private func sortValue(_ value: JSONValue?) -> String { value?.boolValue.map { $0 ? "1" : "0" } ?? value?.stringValue ?? "" }
    private func value(_ row: JSONValue, _ field: String) -> JSONValue? { field.split(separator: ".").reduce(Optional(row)) { $0?[String($1)] } }
    private func matches(_ row: JSONValue, _ filter: JSONValue) throws -> Bool {
        let actual = value(row, filter["field"]?.stringValue ?? "") ?? .null
        switch filter["type"]?.stringValue {
        case "equals": return actual == (filter["value"] ?? .null)
        case "equalsAny":
            let expected = filter["value"]?.arrayValue ?? []
            if filter["field"] == "salesChannels.salesChannelId" { return (row["salesChannels"]?.arrayValue ?? []).contains { expected.contains($0["salesChannelId"] ?? .null) } }
            return expected.contains(actual)
        case "not": return try !(filter["queries"]?.arrayValue ?? []).allSatisfy { try matches(row, $0) }
        case "range":
            return (filter["parameters"]?.objectValue ?? [:]).allSatisfy { key, bound in
                let comparison = sortValue(actual).compare(sortValue(bound))
                switch key { case "gte": return comparison != .orderedAscending; case "lte": return comparison != .orderedDescending; case "lt": return comparison == .orderedAscending; default: return false }
            }
        default: throw unsupported("Unknown review filter: \(filter)")
        }
    }
    private func fail(_ flag: String) throws { if failures.remove(flag) != nil { throw ApiError.unexpected(status: 422, message: "Fixture request failed. Please retry.") } }
    private func unsupported(_ path: String) -> ApiError { .unexpected(status: 500, message: "Unsupported promotion fixture route: \(path)") }
    private func response(_ body: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: body.encoded()) }
}
#endif
