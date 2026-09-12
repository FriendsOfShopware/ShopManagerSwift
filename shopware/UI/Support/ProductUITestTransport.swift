#if DEBUG
import Foundation
import ShopwareAdminAPI

/// Deterministic product API for module tests. Required fields and relation
/// payloads follow Core's definitions; unknown requests fail explicitly.
actor ProductUITestTransport: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    private(set) var products: [JSONValue]
    private var failures: Set<String>
    private let privileges: [String]
    private var media: [JSONValue]
    init(arguments: [String] = [], images: [String: String] = [:], count: Int = 3, variants: Int = 32) {
        failures = Set(arguments)
        var privileges = ["product:read", "currency:read", "tax:read", "product_manufacturer:read", "custom_field_set:read", "custom_field:read", "category:read", "sales_channel:read", "property_group_option:read", "unit:read", "delivery_time:read", "tag:read", "media:read", "product_review:read"]
        if !arguments.contains("--read-only") {
            privileges += ["product:create", "product:update", "product:delete", "media:create", "media:update"]
            for entity in ["product_media", "product_visibility", "product_category", "product_property", "product_tag"] { privileges += [entity + ":create", entity + ":delete"] }
        }
        if arguments.contains("--editor-only") { privileges.removeAll { $0 == "product:delete" || $0 == "product:create" } }
        if arguments.contains("--deleter-only") { privileges.removeAll { $0 == "product:update" || $0 == "product:create" } }
        self.privileges = privileges
        media = (0..<3).map { index in Self.image(index, url: images["image-\(index + 1)"]) }
        products = arguments.contains("--empty-products") ? [] : (0..<count).map { Self.product($0, images: images, variants: variants) }
        if !products.isEmpty { products += (0..<variants).map { index in
            var row = Self.product(0, images: images, variants: 0).objectValue!
            row["id"] = .string("variant-\(index)"); row["parentId"] = "product-0"
            row["productNumber"] = .string(String(format: "SW-100-%03d", index)); row["stock"] = .int(index + 1)
            row["options"] = .array([.object(["id": .string("option-\(index)"), "name": .string("Sand / Size \(index + 1)"), "group": .object(["id": "size", "name": "Size"])])])
            return .object(row)
        } }
    }
    func inject(_ flag: String) { failures.insert(flag) }
    static let channels: [JSONValue] = [.object(["id": "channel", "name": "Storefront"]), .object(["id": "outlet", "name": "Outlet"])]
    static let categories: [JSONValue] = [.object(["id": "category", "name": "Clothing"]), .object(["id": "new-category", "name": "Summer collection"])]
    static let properties: [JSONValue] = [.object(["id": "property", "name": "Linen", "group": .object(["id": "material", "name": "Material"])])]
    static let currencies: [JSONValue] = [
        .object(["id": "usd", "isoCode": "USD", "factor": .number(1.1)]),
        .object(["id": .string(ShopwareDefaults.currencyID), "isoCode": "EUR", "factor": .number(1)]),
    ]
    static func image(_ index: Int, url: String? = nil) -> JSONValue {
        .object(["id": .string("image-\(index + 1)"), "fileName": .string(["linen-shirt-sand", "everyday-tote", "ceramic-coffee-cup"][index]), "fileExtension": "png", "mimeType": "image/png", "url": url.map(JSONValue.string) ?? .null])
    }
    static func product(_ index: Int, images: [String: String] = [:], variants: Int = 32) -> JSONValue {
        let media = Self.image(index % 3, url: images["image-\(index % 3 + 1)"])
        let mapping: JSONValue = .object(["id": .string("media-mapping-\(index)"), "mediaId": media["id"]!, "productId": .string("product-\(index)"), "position": .int(0), "media": media])
        return .object([
            "id": .string("product-\(index)"), "parentId": .null,
            "name": .string(["Linen shirt in sand", "Everyday canvas tote", "Ceramic coffee cup"][index % 3]),
            "productNumber": .string("SW-\(100 + index)"), "active": .bool(index % 3 != 2), "stock": .int(index % 3 == 2 ? -1 : 28), "availableStock": .int(index % 3 == 2 ? -1 : 25),
            "sales": .int(index * 10), "childCount": .int(index == 0 ? variants : 0), "createdAt": "2026-09-01T10:00:00.123Z",
            "taxId": "tax", "tax": .object(["id": "tax", "name": "Standard rate", "taxRate": .number(19)]),
            "price": .array([
                .object(["currencyId": "usd", "gross": .number(59.5), "net": .number(50), "linked": true]),
                .object(["currencyId": .string(ShopwareDefaults.currencyID), "gross": .number(49.123456789), "net": .number(41.28), "linked": false,
                         "listPrice": .object(["gross": .number(69), "net": .number(57.98), "linked": false])]),
            ]),
            "prices": .array([]), "ean": "1234567890123", "manufacturerNumber": "LINEN-SAND",
            "manufacturerId": "manufacturer", "manufacturer": .object(["id": "manufacturer", "name": "Studio Essentials"]),
            "description": "<p>A breathable <strong>linen shirt</strong> for warm days.</p>",
            "metaTitle": "Linen shirt | Studio Essentials", "metaDescription": "Made for warm days.", "keywords": "linen,shirt",
            "isCloseout": false, "minPurchase": .int(1), "purchaseSteps": .int(1), "maxPurchase": .null, "shippingFree": false,
            "restockTime": .int(7), "releaseDate": "2026-09-01T10:00:00.123Z", "weight": .number(0.25),
            "media": .array([mapping]), "coverId": mapping["id"]!, "cover": mapping,
            "categories": .array([categories[0]]), "properties": .array(properties), "tags": .array([]), "options": .array([]),
            "visibilities": .array([.object(["id": .string("visibility-\(index)"), "salesChannelId": "channel", "visibility": .int(10), "salesChannel": channels[0]])]),
            "customFields": .object(["product_reference": "SUMMER-26", "unexposed": "preserved"]),
        ])
    }
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "product-ui.test" else { throw unsupported(request.url) }
        let path = url.path, payload = request.body.flatMap(JSONValue.parse) ?? .object([:])
        if path == "/api/oauth/token" { return response(.object(["access_token": "fixture", "expires_in": .int(3600)])) }
        requests.append(request)
        if path == "/api/_info/me" {
            try fail("--fail-permissions-once")
            return response(.object(["data": .object(["id": "user", "admin": false, "aclRoles": .array([.object(["privileges": .array(privileges.map(JSONValue.string))])])])]))
        }
        if path.hasPrefix("/api/search/"), request.method == .post {
            var rows: [JSONValue]
            switch url.lastPathComponent {
            case "product":
                try fail(payload["ids"] == nil ? "--fail-list-once" : "--fail-detail-once")
                if payload["page"]?.intValue == 2 { try fail("--fail-page-once") }
                rows = products
            case "currency": try fail("--fail-currency-once"); rows = Self.currencies
            case "tax": rows = [.object(["id": "tax", "name": "Standard rate", "taxRate": .number(19)])]
            case "sales-channel": rows = Self.channels
            case "category": rows = Self.categories
            case "property-group-option": rows = Self.properties
            case "tag": rows = [.object(["id": "tag", "name": "Summer"])]
            case "unit": rows = [.object(["id": "unit", "name": "Piece"])]
            case "delivery-time": rows = [.object(["id": "delivery", "name": "2–3 days"])]
            case "product-manufacturer": rows = [.object(["id": "manufacturer", "name": "Studio Essentials"])]
            case "media": rows = media
            case "custom-field-set":
                try fail("--fail-fields-once")
                rows = [.object(["id": "product-fields", "name": "product_fields", "active": true,
                    "config": .object(["label": .object(["en-GB": "Additional information", "de-DE": "Zusätzliche Informationen"])]),
                    "customFields": .array([.object(["id": "field", "name": "product_reference", "type": "text", "active": true, "config": .object(["label": .object(["en-GB": "Reference", "de-DE": "Referenz"]), "componentName": "sw-text-field"])])])])]
            default: throw unsupported(path)
            }
            if let ids = payload["ids"]?.arrayValue { rows = rows.filter { ids.contains($0["id"] ?? .null) } }
            if url.lastPathComponent != "custom-field-set" { for filter in payload["filter"]?.arrayValue ?? [] { rows = try rows.filter { try matches($0, filter) } } }
            if let term = payload["term"]?.stringValue, !term.isEmpty { rows = rows.filter { row in ["name", "productNumber", "fileName"].contains { row[$0]?.stringValue?.localizedCaseInsensitiveContains(term) == true } } }
            rows.sort { a, b in
                for sorting in payload["sort"]?.arrayValue ?? [] {
                    let key = sorting["field"]?.stringValue ?? "id", left = values(a, key).first, right = values(b, key).first
                    let comparison: ComparisonResult
                    if let lhs = left?.doubleValue, let rhs = right?.doubleValue { comparison = lhs == rhs ? .orderedSame : lhs < rhs ? .orderedAscending : .orderedDescending }
                    else { comparison = (left?.stringValue ?? "").compare(right?.stringValue ?? "", options: [.numeric, .caseInsensitive]) }
                    if comparison != .orderedSame { return sorting["order"] == "DESC" ? comparison == .orderedDescending : comparison == .orderedAscending }
                }
                return false
            }
            let total = rows.count, page = payload["page"]?.intValue ?? 1, limit = payload["limit"]?.intValue ?? 25
            return response(.object(["total": .int(total), "data": .array(Array(rows.dropFirst(max(0, page - 1) * limit).prefix(limit)))]))
        }
        if path == "/api/media", request.method == .post {
            try require("media:create")
            guard let id = payload["id"]?.stringValue, !media.contains(where: { $0["id"]?.stringValue == id }) else { throw unsupported("Missing media ID") }
            media.append(payload)
            return HTTPResponse(status: 204, body: Data())
        }
        if path.hasPrefix("/api/_action/media/"), path.hasSuffix("/upload"), request.method == .post {
            try require("media:update")
            let id = url.deletingLastPathComponent().lastPathComponent
            guard let index = media.firstIndex(where: { $0["id"]?.stringValue == id }), request.body?.isEmpty == false else { throw unsupported("Missing uploaded media") }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            media[index] = .object(["id": .string(id), "fileName": .string(query.first { $0.name == "fileName" }?.value ?? "uploaded"),
                                    "fileExtension": .string(query.first { $0.name == "extension" }?.value ?? "png"), "mimeType": "image/png"])
            return HTTPResponse(status: 204, body: Data())
        }
        if path == "/api/product", request.method == .post {
            try require("product:create"); try fail("--fail-save-once")
            guard payload["name"]?.stringValue?.isEmpty == false, payload["productNumber"]?.stringValue?.isEmpty == false,
                  payload["taxId"]?.stringValue != nil, payload["stock"]?.intValue != nil,
                  let id = payload["id"], !products.contains(where: { $0["id"] == id }) else { throw unsupported("Missing required product fields") }
            try validatePrices(payload["price"])
            var row = Self.product(2, variants: 0).objectValue!
            row["media"] = .array([]); row["cover"] = .null; row["coverId"] = .null; row["visibilities"] = .array([])
            row.merge(payload.objectValue ?? [:]) { _, new in new }; products.append(.object(row))
            return HTTPResponse(status: 204, body: Data())
        }
        if path.hasPrefix("/api/product/"), let index = products.firstIndex(where: { $0["id"]?.stringValue == url.lastPathComponent }) {
            if request.method == .patch {
                try require("product:update"); try fail("--fail-save-once")
                if payload["media"] != nil { try fail("--fail-attach-once") }
                if let prices = payload["price"] { try validatePrices(prices) }
                var row = products[index].objectValue!
                try mergeProduct(payload, into: &row)
                products[index] = .object(row)
                return HTTPResponse(status: 204, body: Data())
            }
            if request.method == .delete {
                try require("product:delete"); try fail("--fail-delete-\(url.lastPathComponent)-once")
                let id = products[index]["id"]
                products.removeAll { $0["id"] == id || $0["parentId"] == id }
                return HTTPResponse(status: 204, body: Data())
            }
        }
        if path == "/api/_action/sync", request.method == .post {
            try require("product:update"); try fail("--fail-assignments-once")
            guard request.headers["single-operation"] == "1", let operations = payload.objectValue else { throw unsupported("Non-atomic product transaction") }
            var updated = products
            for operation in operations.values {
                let entity = operation["entity"]?.stringValue ?? "", action = operation["action"]?.stringValue ?? ""
                if action == "delete" {
                    try require(entity + ":delete")
                    guard ["product_visibility", "product_media", "product_category", "product_property", "product_tag"].contains(entity) else { throw unsupported("Unknown relation") }
                    for deletion in operation["payload"]?.arrayValue ?? [] {
                        if ["product_category", "product_property", "product_tag"].contains(entity) {
                            guard deletion["productVersionId"]?.stringValue == ShopwareDefaults.liveVersionID else { throw unsupported("Missing composite version key") }
                            if entity == "product_category", deletion["categoryVersionId"]?.stringValue != ShopwareDefaults.liveVersionID { throw unsupported("Missing category version key") }
                        }
                        if entity == "product_media" || entity == "product_visibility" {
                            let key = entity == "product_media" ? "media" : "visibilities"
                            for index in updated.indices {
                                var row = updated[index].objectValue!
                                row[key] = .array((row[key]?.arrayValue ?? []).filter { $0["id"] != deletion["id"] })
                                updated[index] = .object(row)
                            }
                        }
                    }
                } else if entity == "product" && action == "upsert" {
                    for patch in operation["payload"]?.arrayValue ?? [] {
                        guard let index = updated.firstIndex(where: { $0["id"] == patch["id"] }) else { throw unsupported("Unknown product") }
                        var row = updated[index].objectValue!
                        try mergeProduct(patch, into: &row); updated[index] = .object(row)
                    }
                } else { throw unsupported("Invalid sync operation") }
            }
            products = updated
            return response(.object([:]))
        }
        throw unsupported(path)
    }
    private func mergeProduct(_ patch: JSONValue, into row: inout [String: JSONValue]) throws {
        let writable = Set(["id", "name", "productNumber", "active", "ean", "manufacturerNumber", "manufacturerId", "description", "metaTitle", "metaDescription", "keywords", "customFields", "stock", "isCloseout", "shippingFree", "deliveryTimeId", "unitId", "packUnit", "packUnitPlural", "releaseDate", "price", "media", "coverId", "categories", "properties", "tags", "visibilities"] + ProductInventoryField.allCases.map(\.rawValue))
        guard Set(patch.objectValue?.keys.map { $0 } ?? []).isSubset(of: writable) else { throw unsupported("Unexpected product field") }
        let oldMedia = row["media"]?.arrayValue ?? []
        row.merge(patch.objectValue ?? [:]) { _, new in new }
        if let mappings = patch["visibilities"]?.arrayValue {
            try require("product_visibility:create")
            row["visibilities"] = .array(try mappings.map { mapping in
                guard mapping["id"]?.stringValue != nil, mapping["salesChannelId"]?.stringValue != nil, [10, 20, 30].contains(mapping["visibility"]?.intValue ?? 0) else { throw unsupported("Missing required visibility fields") }
                var value = mapping.objectValue!; value["salesChannel"] = Self.channels.first { $0["id"] == mapping["salesChannelId"] }; return .object(value)
            })
        }
        for (key, references) in [("categories", Self.categories), ("properties", Self.properties), ("tags", [.object(["id": "tag", "name": "Summer"])])] {
            if let mappings = patch[key]?.arrayValue { row[key] = .array(mappings.map { mapping in references.first { $0["id"] == mapping["id"] } ?? mapping }) }
        }
        if let mappings = patch["media"]?.arrayValue {
            try require("product_media:create")
            var current = oldMedia
            for mapping in mappings {
                guard mapping["id"]?.stringValue != nil, let mediaID = mapping["mediaId"], let media = media.first(where: { $0["id"] == mediaID }) else { throw unsupported("Missing media mapping fields") }
                var value = mapping.objectValue!; value["media"] = media; value["productId"] = row["id"]
                if let index = current.firstIndex(where: { $0["id"] == mapping["id"] }) { current[index] = .object(value) } else { current.append(.object(value)) }
            }
            row["media"] = .array(current)
        }
        if patch["coverId"] != nil || patch["media"] != nil { row["cover"] = row["media"]?.arrayValue?.first { $0["id"] == row["coverId"] } ?? .null }
    }
    private func validatePrices(_ value: JSONValue?) throws {
        guard let prices = value?.arrayValue, !prices.isEmpty else { throw unsupported("Missing required product price") }
        for price in prices {
            guard price["currencyId"]?.stringValue != nil, let gross = price["gross"]?.doubleValue, gross >= 0, let net = price["net"]?.doubleValue, net >= 0, price["linked"]?.boolValue != nil else { throw unsupported("Invalid product price") }
        }
    }
    private func values(_ row: JSONValue, _ path: String) -> [JSONValue] {
        path.split(separator: ".").reduce([row]) { rows, key in rows.flatMap { value in
            if let list = value.arrayValue { return list.compactMap { $0[String(key)] } }
            return value[String(key)].map { [$0] } ?? []
        } }
    }
    private func matches(_ row: JSONValue, _ filter: JSONValue) throws -> Bool {
        let actual = values(row, filter["field"]?.stringValue ?? "")
        switch filter["type"]?.stringValue {
        case "equals": return actual.isEmpty ? filter["value"] == .null : actual.contains(filter["value"] ?? .null)
        case "equalsAny": return actual.contains { (filter["value"]?.arrayValue ?? []).contains($0) }
        case "contains": return actual.contains { $0.stringValue?.localizedCaseInsensitiveContains(filter["value"]?.stringValue ?? "") == true }
        case "not": return try !(filter["queries"]?.arrayValue ?? []).allSatisfy { try matches(row, $0) }
        case "range":
            let actual = filter["field"] == "price" ? row["price"]?.arrayValue?.first { $0["currencyId"]?.stringValue == ShopwareDefaults.currencyID }?["gross"] : actual.first
            return (filter["parameters"]?.objectValue ?? [:]).allSatisfy { key, bound in
                let comparison: ComparisonResult
                if let left = actual?.doubleValue, let right = bound.doubleValue { comparison = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending }
                else { comparison = (actual?.stringValue ?? "").compare(bound.stringValue ?? "") }
                switch key { case "gte": return comparison != .orderedAscending; case "lte": return comparison != .orderedDescending; case "lt": return comparison == .orderedAscending; default: return false }
            }
        default: throw unsupported("Unknown product filter")
        }
    }
    private func require(_ privilege: String) throws { guard privileges.contains(privilege) else { throw ApiError.unexpected(status: 403, message: "Read only") } }
    private func fail(_ flag: String) throws { if failures.remove(flag) != nil { throw ApiError.unexpected(status: 422, message: "Fixture request failed. Please retry.") } }
    private func unsupported(_ message: String) -> ApiError { .unexpected(status: 400, message: "Unsupported product fixture request: " + message) }
    private func response(_ body: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: body.encoded()) }
}
#endif
