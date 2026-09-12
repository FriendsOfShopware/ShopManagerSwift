#if DEBUG
import Foundation
import ShopwareAdminAPI

/// Strict offline Shopware fixture shared by the order model and UI tests.
actor OrderUITestTransport: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    private(set) var live: [JSONValue]
    private(set) var drafts: [String: [JSONValue]] = [:]
    private var failures: Set<String>
    private let readOnly: Bool
    private var history: [JSONValue] = []
    private var cartItems: [JSONValue] = []

    init(arguments: [String] = [], count: Int = 3) {
        failures = Set(arguments); readOnly = arguments.contains("--read-only")
        live = arguments.contains("--empty-orders") ? [] : (0..<count).map { Self.order($0, empty: arguments.contains("--empty-details")) }
    }
    func inject(_ flag: String) { failures.insert(flag) }

    static func state(_ technical: String) -> JSONValue {
        .object(["id": .string(technical), "technicalName": .string(technical), "name": .string(["open": "Open", "in_progress": "In progress", "completed": "Completed", "paid": "Paid", "shipped": "Shipped", "failed": "Failed"][technical] ?? technical)])
    }
    static var address: JSONValue {
        .object(["id": "address", "customerId": "customer", "firstName": "Alexandra", "lastName": "Montgomery",
                 "street": "123 Meadow Avenue", "zipcode": "10115", "city": "Berlin", "countryId": "country",
                 "country": .object(["id": "country", "name": "Germany"]), "phoneNumber": "+49 30 12345678"])
    }
    static var customer: JSONValue {
        .object(["id": "customer", "firstName": "Alexandra", "lastName": "Montgomery", "email": "alexandra@example.test", "customerNumber": "SW10042", "active": true,
                 "salesChannelId": "channel", "salesChannel": .object(["id": "channel", "name": "Storefront"]), "languageId": "language",
                 "defaultBillingAddressId": "address", "defaultShippingAddressId": "address", "defaultBillingAddress": address, "defaultShippingAddress": address])
    }
    static func item(_ id: String = "item", label: String = "Linen shirt · Sand / M", price: Double = 49.5) -> JSONValue {
        .object(["id": .string(id), "label": .string(label), "quantity": 2, "type": "product", "position": 1,
                 "unitPrice": .number(price), "totalPrice": .number(price * 2), "productId": "product",
                 "priceDefinition": .object(["price": .number(price), "quantity": 2, "isCalculated": true, "taxRules": .array([.object(["taxRate": 19, "percentage": 100])])]),
                 "payload": .object(["productNumber": "SW-10001"])])
    }
    static func order(_ index: Int, empty: Bool = false) -> JSONValue {
        let id = "order-\(index)"
        return .object(["id": .string(id), "orderNumber": .string("1000\(index + 1)"), "orderDateTime": .string(String(format: "2026-09-%02dT10:30:00.000+00:00", 11 - index % 10)),
            "salesChannelId": "channel", "salesChannel": .object(["id": "channel", "name": "Storefront"]), "language": .object(["id": "language", "name": "English"]),
            "orderCustomer": .object(["id": .string("customer-" + id), "customerId": "customer", "firstName": index == 1 ? "Sam" : "Alexandra", "lastName": index == 1 ? "Rivera" : "Montgomery", "email": "alexandra@example.test", "customerNumber": "SW10042", "company": "Meadow Design Studio"]),
            "stateMachineState": state(index == 2 ? "completed" : "open"), "deepLinkCode": "order-link", "billingAddress": address,
            "currency": .object(["id": "currency", "isoCode": "EUR"]), "amountTotal": 103.9, "amountNet": 87.31, "shippingTotal": 4.9, "positionPrice": 99,
            "price": .object(["positionPrice": 99, "totalPrice": 103.9, "netPrice": 87.31, "rawTotal": 103.9, "taxStatus": "gross", "calculatedTaxes": .array([.object(["taxRate": 19, "tax": 16.59])])]),
            "lineItems": .array([item()]), "internalComment": "Pack with care.", "customerComment": "Please leave at reception.",
            "transactions": .array([.object(["id": .string("payment-" + id), "stateMachineState": state("open"), "createdAt": "2026-09-11T10:31:00.000+00:00", "paymentMethod": .object(["id": "payment", "name": "Invoice"]), "amount": .object(["totalPrice": 103.9])])]),
            "deliveries": .array([.object(["id": .string("delivery-" + id), "stateMachineState": state("open"), "shippingMethod": .object(["id": "shipping", "name": "Standard shipping", "trackingUrl": "https://tracking.example.test/%s"]), "shippingOrderAddress": address, "trackingCodes": .array(["TRACK123"]), "shippingCosts": .object(["unitPrice": 4.9, "totalPrice": 4.9])])]),
            "documents": empty ? .array([]) : .array([.object(["id": .string("invoice-" + id), "deepLinkCode": "document-link", "documentType": .object(["id": "invoice", "technicalName": "invoice", "name": "Invoice"]), "createdAt": "2026-09-11T11:00:00.000+00:00", "config": .object(["documentNumber": "INV-10001", "custom": .object(["invoiceNumber": "INV-10001"])])])]),
            "tags": .array([.object(["id": "priority", "name": "Priority"])]), "customFields": .object([:])])
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "order-ui.test" else { throw ApiError.network(message: "Order fixtures reject non-fixture hosts.", underlying: nil) }
        let path = url.path, payload = request.body.flatMap(JSONValue.parse) ?? .object([:])
        if path.hasSuffix("/oauth/token") { return response(.object(["access_token": "fixture", "expires_in": 3600])) }
        requests.append(request)
        let version = request.headers["sw-version-id"] ?? OrderApi.liveVersionId
        if path.hasSuffix("/_info/me") {
            try fail("--fail-permissions-once")
            return response(.object(["data": .object(["id": "admin", "admin": .bool(!readOnly), "aclRoles": .array([.object(["privileges": .array(["order:read", "document:read", "state_machine_history:read"])])])])]))
        }
        if path.contains("/search/") {
            let entity = url.lastPathComponent
            var rows: [JSONValue]
            switch entity {
            case "order":
                let detail = (payload["filter"]?.arrayValue ?? []).contains { $0["field"]?.stringValue == "id" }
                try fail(detail ? "--fail-detail-once" : "--fail-list-once")
                if version != OrderApi.liveVersionId && drafts[version] == nil { throw ApiError.notFound(message: "Draft not found") }
                rows = version == OrderApi.liveVersionId ? live : drafts[version] ?? []
            case "state-machine-history": try fail("--fail-history-once"); rows = history
            case "state-machine-state": rows = [Self.state("open"), Self.state("in_progress"), Self.state("completed")]
            case "customer": rows = [Self.customer]
            case "customer-address": rows = [Self.address]
            case "product": rows = [.object(["id": "product", "name": "Ceramic mug", "productNumber": "SW-10002"])]
            case "country": rows = [.object(["id": "country", "name": "Germany", "active": true])]
            case "tag": rows = [.object(["id": "priority", "name": "Priority"])]
            case "currency": rows = [.object(["id": "currency", "name": "Euro", "isoCode": "EUR"])]
            case "language": rows = [.object(["id": "language", "name": "English"])]
            case "payment-method": rows = [.object(["id": "payment", "name": "Invoice", "active": true])]
            case "shipping-method": rows = [.object(["id": "shipping", "name": "Standard shipping", "active": true])]
            case "sales-channel": rows = [.object(["id": "channel", "name": "Storefront", "active": true])]
            case "salutation", "country-state", "custom-field-set": rows = []
            default: throw unsupported(path)
            }
            if let ids = payload["ids"]?.arrayValue { rows = rows.filter { ids.contains($0["id"] ?? .null) } }
            if ["order", "customer", "customer-address", "state-machine-history"].contains(entity) {
                for filter in payload["filter"]?.arrayValue ?? [] { rows = rows.filter { matches($0, filter) } }
            }
            if let term = payload["term"]?.stringValue, !term.isEmpty { rows = rows.filter { String(decoding: $0.encoded(), as: UTF8.self).localizedCaseInsensitiveContains(term) } }
            rows.sort { a, b in
                for sort in payload["sort"]?.arrayValue ?? [] {
                    let field = sort["field"]?.stringValue ?? "id", lhs = value(a, field), rhs = value(b, field)
                    let cmp: ComparisonResult
                    if let a = lhs?.doubleValue, let b = rhs?.doubleValue { cmp = a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending }
                    else { cmp = (lhs?.stringValue ?? "").compare(rhs?.stringValue ?? "", options: [.numeric, .caseInsensitive]) }
                    if cmp != .orderedSame { return sort["order"]?.stringValue == "DESC" ? cmp == .orderedDescending : cmp == .orderedAscending }
                }
                return false
            }
            let total = rows.count, page = payload["page"]?.intValue ?? 1, limit = payload["limit"]?.intValue ?? 100
            return response(.object(["total": .int(total), "data": .array(Array(rows.dropFirst(max(0, page - 1) * limit).prefix(limit)))]))
        }
        if path.contains("/_action/state-machine/") {
            let parts = path.split(separator: "/"); let entity = String(parts[parts.count - 3])
            let action = entity == "order_transaction" ? "pay" : entity == "order_delivery" ? "ship" : "process"
            let target = entity == "order_transaction" ? "paid" : entity == "order_delivery" ? "shipped" : "in_progress"
            return response(.object(["transitions": .array([.object(["actionName": .string(action), "name": .string(Self.state(target)["name"]?.stringValue ?? target), "toStateName": .string(target), "url": .string("/_action/" + entity + "/state/" + action)])])]))
        }
        if request.method == .get && (path.contains("/_action/document/") || path.hasSuffix("/preview")) { return HTTPResponse(status: 200, body: Self.pdf) }
        guard !readOnly else { throw ApiError.unexpected(status: 403, message: "Read-only fixture") }
        if path.contains("/_action/version/merge/order/") {
            try fail("--fail-merge-once")
            guard let rows = drafts.removeValue(forKey: url.lastPathComponent) else { throw ApiError.notFound(message: "Draft not found") }
            live = rows
            if failures.remove("--lose-merge-response") != nil { throw ApiError.network(message: "Save response lost", underlying: nil) }
            return empty()
        }
        if path.contains("/_action/version/order/") {
            guard let id = payload["versionId"]?.stringValue else { throw unsupported(path) }
            drafts[id] = live
            return response(.object(["versionId": .string(id)]))
        }
        if path.contains("/_action/version/") {
            let components = path.split(separator: "/"), id = String(components[components.count - 3])
            guard drafts.removeValue(forKey: id) != nil else { throw ApiError.notFound(message: "Draft not found") }
            return empty()
        }
        if path.contains("/state/"), let entityIndex = path.split(separator: "/").firstIndex(of: "_action") {
            try fail("--fail-status-once")
            let parts = path.split(separator: "/"), entity = String(parts[entityIndex + 1]), id = String(parts[entityIndex + 2])
            let target = entity == "order_transaction" ? "paid" : entity == "order_delivery" ? "shipped" : "in_progress"
            changeState(entity: entity, id: id, target: target)
            return empty()
        }
        if path.contains("/_action/order/document/") && path.hasSuffix("/create") {
            if failures.remove("--fail-document-once") != nil {
                let id = payload.arrayValue?.first?["orderId"]?.stringValue ?? "order-0"
                return response(.object(["data": .array([]), "errors": .object([id: .array([.object(["code": "DOCUMENT_ERROR", "detail": "Document fixture rejected the settings."])])])]))
            }
            guard let operation = payload.arrayValue?.first, let id = operation["orderId"]?.stringValue, let index = live.firstIndex(where: { $0["id"]?.stringValue == id }) else { throw unsupported(path) }
            let documentID = "generated-\((live[index]["documents"]?.arrayValue ?? []).count)"
            let type = String(path.split(separator: "/").dropLast().last ?? "invoice")
            var document: [String: JSONValue] = ["id": .string(documentID), "deepLinkCode": "document-link", "documentType": .object(["technicalName": .string(type), "name": .string(type)]), "config": operation["config"] ?? .object([:]), "static": operation["static"] ?? false]
            document["referencedDocumentId"] = operation["referencedDocumentId"]
            var order = live[index].objectValue ?? [:]; order["documents"] = .array((order["documents"]?.arrayValue ?? []) + [.object(document)]); live[index] = .object(order)
            return response(.object(["data": .array([.object(["documentId": .string(documentID), "documentDeepLink": "document-link"])]), "errors": .object([:])]))
        }
        if path.contains("/_action/document/") && path.hasSuffix("/upload") {
            try fail("--fail-upload-once")
            let id = String(path.split(separator: "/").dropLast().last ?? "")
            for index in live.indices {
                var row = live[index].objectValue ?? [:]
                row["documents"] = .array((row["documents"]?.arrayValue ?? []).map {
                    $0["id"]?.stringValue == id ? merge($0, .object(["documentMediaFileId": "uploaded-pdf"])) : $0
                })
                live[index] = .object(row)
            }
            return empty()
        }
        if path.hasSuffix("/_action/sync") {
            try fail("--fail-save-once")
            guard let operations = payload.objectValue else { throw unsupported(path) }
            for operation in operations.values {
                if operation["entity"] == "order", let item = operation["payload"]?.arrayValue?.first, let id = item["id"]?.stringValue { try updateOrder(id, patch: item, version: version) }
            }
            for operation in operations.values where operation["entity"] == "order_tag" {
                for tag in operation["payload"]?.arrayValue ?? [] {
                    let id = tag["orderId"]?.stringValue ?? "", rows = drafts[version] ?? live
                    if let row = rows.first(where: { $0["id"]?.stringValue == id }) {
                        try updateOrder(id, patch: .object(["tags": .array((row["tags"]?.arrayValue ?? []).filter { $0["id"] != tag["tagId"] })]), version: version)
                    }
                }
            }
            return response(.object(["success": true]))
        }
        if request.method == .patch && path.contains("/order/") {
            try fail("--fail-save-once"); try updateOrder(url.lastPathComponent, patch: payload, version: version); return empty()
        }
        if request.method == .patch && path.contains("/order-delivery/") {
            try fail("--fail-tracking-once")
            for order in live {
                if let delivery = order["deliveries"]?.arrayValue?.first(where: { $0["id"]?.stringValue == url.lastPathComponent }), let id = order["id"]?.stringValue {
                    try updateOrder(id, patch: .object(["deliveries": .array([merge(delivery, payload)])]), version: version)
                }
            }
            return empty()
        }
        if request.method == .delete && path.contains("/order-line-item/") {
            var rows = drafts[version] ?? []
            for i in rows.indices { var row = rows[i].objectValue ?? [:]; row["lineItems"] = .array((row["lineItems"]?.arrayValue ?? []).filter { $0["id"]?.stringValue != url.lastPathComponent }); rows[i] = .object(row) }
            drafts[version] = rows; return empty()
        }
        if request.method == .delete && path.contains("/order/") {
            if url.lastPathComponent == "order-1" { try fail("--fail-delete-once") }
            live.removeAll { $0["id"]?.stringValue == url.lastPathComponent }; return empty()
        }
        if path.contains("/_action/order/") {
            guard let rows = drafts[version], let id = path.split(separator: "/").dropFirst(3).first.map(String.init), let row = rows.first(where: { $0["id"]?.stringValue == id }) else { throw unsupported(path) }
            if path.hasSuffix("/recalculate") {
                if failures.remove("--fail-recalculate-once") != nil { return response(.object(["errors": .object(["stock": .object(["message": "Insufficient stock for this quantity.", "blockOrder": true])])])) }
                try recalculate(id, version: version); return empty()
            }
            var items = row["lineItems"]?.arrayValue ?? []
            if path.contains("/product/") { items.append(Self.item("added-product", label: "Ceramic mug", price: 19)) }
            else if path.hasSuffix("/lineItem") || path.hasSuffix("/creditItem") {
                var item = payload.objectValue ?? [:]; item["id"] = payload["identifier"]; item["unitPrice"] = payload["priceDefinition"]?["price"]; items.append(.object(item))
            } else if path.hasSuffix("/promotion-item") || path.hasSuffix("/applyAutomaticPromotions") || path.hasSuffix("/toggleAutomaticPromotions") {
                items.append(.object(["id": "promotion", "type": "promotion", "label": "Welcome discount", "quantity": 1, "unitPrice": -5, "totalPrice": -5]))
            } else { throw unsupported(path) }
            try updateOrder(id, patch: .object(["lineItems": .array(items)]), version: version)
            try recalculate(id, version: version); return response(.object(["errors": .object([:])]))
        }
        if path.hasSuffix("switch-customer") { return response(.object(["sw-context-token": "cart"])) }
        if path.hasSuffix("/context") { return response(.object(["currency": .object(["id": "currency", "isoCode": "EUR"]), "customer": Self.customer, "paymentMethod": .object(["id": "payment", "name": "Invoice"]), "shippingMethod": .object(["id": "shipping", "name": "Standard shipping"])])) }
        if path.contains("/_proxy-order/") {
            var order = Self.order(3, empty: true).objectValue ?? [:]
            let total = cartItems.reduce(0) { $0 + ($1["totalPrice"]?.doubleValue ?? 0) }
            order["id"] = "created-order"; order["lineItems"] = .array(cartItems)
            order["amountTotal"] = .number(total); order["positionPrice"] = .number(total); order["shippingTotal"] = 0
            order["amountNet"] = .number(total / 1.19)
            order["price"] = .object(["rawTotal": .number(total), "taxStatus": "gross", "calculatedTaxes": .array([.object(["taxRate": 19, "tax": .number(total - total / 1.19)])])])
            order["transactions"] = .array((order["transactions"]?.arrayValue ?? []).map { merge($0, .object(["amount": .object(["totalPrice": .number(total)])])) })
            order["deliveries"] = .array((order["deliveries"]?.arrayValue ?? []).map { merge($0, .object(["shippingCosts": .object(["unitPrice": 0, "totalPrice": 0])])) })
            live.append(.object(order)); return response(.object(["id": "created-order"]))
        }
        if path.contains("/checkout/cart") {
            if path.hasSuffix("/line-item"), let items = payload["items"]?.arrayValue {
                for item in items {
                    if let index = cartItems.firstIndex(where: { $0["id"] == item["id"] }) { cartItems[index] = merge(cartItems[index], item) }
                    else { cartItems.append(merge(Self.item(label: "Ceramic mug", price: 19), item)) }
                }
            }
            if request.method == .delete {
                if let ids = payload["ids"]?.arrayValue { cartItems.removeAll { ids.contains($0["id"] ?? .null) } }
                else { cartItems = [] }
            }
            cartItems = cartItems.map { item in
                let unit = item["unitPrice"]?.doubleValue ?? 0, total = unit * Double(item["quantity"]?.intValue ?? 1)
                return merge(item, .object(["totalPrice": .number(total), "price": .object(["unitPrice": .number(unit), "totalPrice": .number(total)])]))
            }
            let total = cartItems.reduce(0) { $0 + ($1["totalPrice"]?.doubleValue ?? 0) }
            return response(.object(["token": "cart", "lineItems": .array(cartItems), "price": .object(["totalPrice": .number(total)]), "errors": .object([:])]))
        }
        throw unsupported(path)
    }

    private func updateOrder(_ id: String, patch: JSONValue, version: String) throws {
        var rows = version == OrderApi.liveVersionId ? live : drafts[version] ?? []
        guard let index = rows.firstIndex(where: { $0["id"]?.stringValue == id }) else { throw ApiError.notFound(message: "Order not found") }
        rows[index] = merge(rows[index], patch)
        if version == OrderApi.liveVersionId { live = rows } else { drafts[version] = rows }
    }
    private func merge(_ original: JSONValue, _ patch: JSONValue) -> JSONValue {
        guard var object = original.objectValue, let fields = patch.objectValue else { return patch }
        for (key, next) in fields {
            if ["lineItems", "deliveries", "transactions"].contains(key), let changes = next.arrayValue {
                var children = object[key]?.arrayValue ?? []
                for child in changes {
                    if let i = children.firstIndex(where: { $0["id"] == child["id"] }) { children[i] = merge(children[i], child) }
                    else { children.append(child) }
                }
                object[key] = .array(children)
            } else if next.objectValue != nil { object[key] = merge(object[key] ?? .object([:]), next) }
            else { object[key] = next }
        }
        return .object(object)
    }
    private func recalculate(_ id: String, version: String) throws {
        guard let row = drafts[version]?.first(where: { $0["id"]?.stringValue == id }) else { throw ApiError.notFound(message: "Draft not found") }
        let items = (row["lineItems"]?.arrayValue ?? []).map { item -> JSONValue in
            let price = item["priceDefinition"]?["price"]?.doubleValue ?? item["unitPrice"]?.doubleValue ?? 0
            return merge(item, .object(["unitPrice": .number(price), "totalPrice": .number(price * Double(item["quantity"]?.intValue ?? 1))]))
        }
        let positions = items.reduce(0) { $0 + ($1["totalPrice"]?.doubleValue ?? 0) }, shipping = row["shippingTotal"]?.doubleValue ?? 0
        try updateOrder(id, patch: .object(["lineItems": .array(items), "amountTotal": .number(positions + shipping), "positionPrice": .number(positions), "price": .object(["rawTotal": .number(positions + shipping)])]), version: version)
    }
    private func changeState(entity: String, id: String, target: String) {
        for i in live.indices {
            var row = live[i].objectValue ?? [:]
            if entity == "order", row["id"]?.stringValue == id { row["stateMachineState"] = Self.state(target) }
            else {
                let key = entity == "order_transaction" ? "transactions" : "deliveries"
                row[key] = .array((row[key]?.arrayValue ?? []).map { $0["id"]?.stringValue == id ? merge($0, .object(["stateMachineState": Self.state(target)])) : $0 })
            }
            live[i] = .object(row)
        }
        history.append(.object(["id": .string("history-\(history.count)"), "referencedId": .string(id), "entityName": .string(entity), "fromStateMachineState": Self.state("open"), "toStateMachineState": Self.state(target), "createdAt": "2026-09-11T13:00:00.000+00:00", "user": .object(["firstName": "Robin", "lastName": "Admin"])]))
    }
    private func value(_ row: JSONValue, _ field: String) -> JSONValue? { field.split(separator: ".").reduce(Optional(row)) { $0?[String($1)] } }
    private func matches(_ row: JSONValue, _ filter: JSONValue) -> Bool {
        let field = filter["field"]?.stringValue ?? "", actual = value(row, field) ?? .null
        switch filter["type"]?.stringValue {
        case "equals": return actual == (filter["value"] ?? .null)
        case "equalsAny": return filter["value"]?.arrayValue?.contains(actual) ?? false
        case "contains": return (actual.stringValue ?? "").localizedCaseInsensitiveContains(filter["value"]?.stringValue ?? "")
        case "multi": let values = (filter["queries"]?.arrayValue ?? []).map { matches(row, $0) }; return filter["operator"] == "OR" ? values.contains(true) : !values.contains(false)
        default: return true
        }
    }
    private func fail(_ flag: String) throws { if failures.remove(flag) != nil { throw ApiError.unexpected(status: 422, message: "Fixture request failed. Please retry.") } }
    private func unsupported(_ path: String) -> ApiError { .unexpected(status: 500, message: "Unsupported order fixture route: \(path)") }
    private func response(_ value: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: value.encoded()) }
    private func empty() -> HTTPResponse { HTTPResponse(status: 204, body: Data()) }
    private static var pdf: Data {
        // Minimal deterministic PDF with valid offsets, usable by Quick Look on every target.
        var text = "%PDF-1.4\n", offsets = [0]
        let stream = "BT /F1 18 Tf 30 130 Td (Order invoice preview) Tj ET\n"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>", "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
        for (i, object) in objects.enumerated() { offsets.append(text.utf8.count); text += "\(i + 1) 0 obj\n\(object)\nendobj\n" }
        let xref = text.utf8.count
        text += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(text.utf8)
    }
}
#endif
