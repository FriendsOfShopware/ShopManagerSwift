#if DEBUG
import Foundation
import ShopwareAdminAPI

actor CustomerUITestTransport: HTTPTransport {
    let emptyOrders: Bool
    private let readOnly: Bool
    private var failures: Set<String>
    private var changedCustomers: [String: JSONValue] = [:]
    private var changedAddresses: [String: JSONValue] = [:]
    private var deletedCustomers = Set<String>()
    private var deletedAddresses = Set<String>()

    init(arguments: [String]) {
        emptyOrders = arguments.contains("--empty-orders")
        readOnly = arguments.contains("--read-only")
        failures = Set(arguments)
    }

    private var address: JSONValue {
        .object(["id": "address", "customerId": "customer", "firstName": "Alexandra", "lastName": "Montgomery-Wellington",
                 "company": "Montgomery & Wellington Design Studio",
                 "street": "123 Long Meadow Avenue", "zipcode": "10115", "city": "Berlin", "countryId": "country",
                 "country": .object(["id": "country", "name": "Germany"]), "phoneNumber": "+49 30 12345678"])
    }

    private var customer: JSONValue {
        .object(["id": "customer", "firstName": "Alexandra", "lastName": "Montgomery-Wellington",
                 "email": "alexandra.montgomery@example.test", "customerNumber": "SW10042", "active": true, "guest": false,
                 "company": "Montgomery & Wellington Design Studio", "accountType": "business", "vatIds": .array(["DE123456789"]),
                 "groupId": "group", "group": .object(["id": "group", "name": "Standard customer group"]),
                 "languageId": "language", "language": .object(["id": "language", "name": "English"]),
                 "salesChannelId": "channel", "salesChannel": .object(["id": "channel", "name": "Storefront"]),
                 "defaultBillingAddressId": "address", "defaultShippingAddressId": "address",
                 "defaultBillingAddress": address, "defaultShippingAddress": address,
                 "createdAt": "2026-01-15T10:00:00.000+00:00", "lastLogin": "2026-09-10T09:15:00.000+00:00",
                 "lastOrderDate": emptyOrders ? .null : "2026-09-10T10:00:00.000+00:00",
                 "birthday": "1990-06-06", "orderCount": .int(emptyOrders ? 0 : 1),
                 "orderTotalAmount": .int(emptyOrders ? 0 : 129), "tags": .array([])])
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "customer-ui.test" else {
            throw ApiError.network(message: "Customer UI fixtures reject non-fixture hosts.", underlying: nil)
        }
        let path = url.path
        let payload = request.body.flatMap { JSONValue.parse($0) }
        if path.hasSuffix("/oauth/token") { return response(.object(["access_token": "fixture", "expires_in": 3600])) }
        if path.hasSuffix("/_info/me") {
            try failOnce("--fail-permissions-once")
            return response(.object(["data": .object(["id": "fixture-admin", "admin": .bool(!readOnly),
                "aclRoles": .array([.object(["privileges": .array(["customer:read", "customer_address:read"])])])])]))
        }
        if path.contains("/search/") {
            let entity = path.components(separatedBy: "/").last ?? ""
            if entity == "customer", payload?["ids"] == nil { try failOnce("--fail-list-once") }
            var rows = entities(entity)
            if let ids = payload?["ids"]?.arrayValue?.compactMap(\.stringValue) {
                rows = rows.filter { ids.contains($0["id"]?.stringValue ?? "") }
            }
            if let term = payload?["term"]?.stringValue, !term.isEmpty {
                rows = rows.filter { String(decoding: $0.encoded(), as: UTF8.self).localizedCaseInsensitiveContains(term) }
            }
            // Exercise the production filter, sort and pagination requests against fixture data.
            if ["customer", "customer-address", "order"].contains(entity) {
                for filter in payload?["filter"]?.arrayValue ?? [] {
                    rows = try rows.filter { try matches($0, filter: filter) }
                }
            }
            let sorting = payload?["sort"]?.arrayValue ?? []
            rows.sort { left, right in
                for sort in sorting {
                    guard let field = sort["field"]?.stringValue else { continue }
                    let a = value(left, field: field)?.stringValue ?? ""
                    let b = value(right, field: field)?.stringValue ?? ""
                    let comparison = a.compare(b, options: [.numeric, .caseInsensitive])
                    if comparison != .orderedSame {
                        return sort["order"]?.stringValue == "DESC" ? comparison == .orderedDescending : comparison == .orderedAscending
                    }
                }
                return false
            }
            let total = rows.count
            let limit = payload?["limit"]?.intValue ?? max(total, 1)
            let page = payload?["page"]?.intValue ?? 1
            rows = Array(rows.dropFirst(max(0, page - 1) * limit).prefix(limit))
            return response(.object(["total": .int(total), "data": .array(rows), "aggregations": .object([:])]))
        }
        if path.hasSuffix("/_action/system-config") { return response(.object(["core.systemWideLoginRegistration.isCustomerBoundToSalesChannel": false])) }
        if path.contains("/_action/number-range/reserve/customer/") { return response(.object(["number": "SW10044"])) }
        if path.hasSuffix("/_action/sync"), let operations = payload?.objectValue {
            try requireWriteAccess()
            for operation in operations.values {
                guard operation["entity"]?.stringValue == "customer", let items = operation["payload"]?.arrayValue else {
                    throw unsupported(request)
                }
                for item in items {
                    guard let id = item["id"]?.stringValue else { throw unsupported(request) }
                    if operation["action"]?.stringValue == "delete" { deletedCustomers.insert(id) }
                    else if operation["action"]?.stringValue == "upsert" {
                        try failOnce("--fail-save-once")
                        if id == "guest" { try failOnce("--fail-bulk-once") }
                        saveCustomer(item)
                    } else { throw unsupported(request) }
                }
            }
            return response(.object(["success": true]))
        }
        if path.hasSuffix("/customer"), request.method == .post, let payload {
            try requireWriteAccess()
            saveCustomer(payload)
            return HTTPResponse(status: 204, body: Data())
        }
        if path.contains("/customer/"), request.method == .delete {
            try requireWriteAccess()
            deletedCustomers.insert(url.lastPathComponent)
            return HTTPResponse(status: 204, body: Data())
        }
        if path.contains("/customer-address/"), request.method == .delete {
            try requireWriteAccess()
            deletedAddresses.insert(url.lastPathComponent)
            return HTTPResponse(status: 204, body: Data())
        }
        if path.contains("/_action/customer-convert/") {
            try requireWriteAccess()
            saveCustomer(.object(["id": .string(url.lastPathComponent), "guest": false]))
            return HTTPResponse(status: 204, body: Data())
        }
        if path.hasSuffix("switch-customer") { return response(.object(["sw-context-token": "fixture-cart"])) }
        if path.hasSuffix("/context") {
            return response(.object(["currency": .object(["id": "currency", "name": "Euro", "isoCode": "EUR"]),
                                     "customer": customer, "paymentMethod": .object(["id": "payment", "name": "Invoice"]),
                                     "shippingMethod": .object(["id": "shipping", "name": "Standard"])]))
        }
        if path.hasSuffix("/checkout/cart") {
            return response(.object(["token": "fixture-cart", "lineItems": .array([]), "price": .object(["totalPrice": 0]), "errors": .object([:])]))
        }
        // Unexpected routes fail visibly instead of silently reaching a live service.
        throw unsupported(request)
    }

    private func entities(_ entity: String) -> [JSONValue] {
        switch entity {
        case "customer":
            var guest = customer.objectValue ?? [:]
            guest.merge(["id": "guest", "firstName": "Sam", "lastName": "Rivera", "company": "", "email": "sam@example.test",
                         "customerNumber": "SW10043", "active": false, "guest": true], uniquingKeysWith: { _, new in new })
            let seeds = [customer, .object(guest)]
            let ids = Set(seeds.compactMap { $0["id"]?.stringValue }).union(changedCustomers.keys)
            return ids.sorted().filter { !deletedCustomers.contains($0) }.compactMap { id in
                guard var row = (changedCustomers[id] ?? seeds.first { $0["id"]?.stringValue == id })?.objectValue else { return nil }
                for (association, key) in [("defaultBillingAddress", "defaultBillingAddressId"), ("defaultShippingAddress", "defaultShippingAddressId")] {
                    if let addressID = row[key]?.stringValue {
                        row[association] = changedAddresses[addressID] ?? (addressID == "address" ? address : nil)
                    }
                }
                if row["groupId"]?.stringValue == "group" { row["group"] = .object(["id": "group", "name": "Standard customer group"]) }
                if row["languageId"]?.stringValue == "language" { row["language"] = .object(["id": "language", "name": "English"]) }
                return .object(row)
            }
        case "customer-address":
            var rows = changedAddresses
            if rows["address"] == nil { rows["address"] = address }
            return rows.keys.sorted().filter { !deletedAddresses.contains($0) }.compactMap { rows[$0] }
        case "customer-group": return [.object(["id": "group", "name": "Standard customer group"])]
        case "language": return [.object(["id": "language", "name": "English"])]
        case "salutation": return [.object(["id": "salutation", "displayName": "Not specified", "salutationKey": "not_specified"])]
        case "country": return [.object(["id": "country", "name": "Germany", "active": true, "postalCodeRequired": true])]
        case "payment-method": return [.object(["id": "payment", "name": "Invoice"])]
        case "shipping-method": return [.object(["id": "shipping", "name": "Standard"])]
        case "currency": return [.object(["id": "currency", "name": "Euro", "isoCode": "EUR"])]
        case "sales-channel": return [.object(["id": "channel", "name": "Storefront", "customerGroupId": "group", "languageId": "language", "countryId": "country"])]
        case "order":
            return emptyOrders ? [] : [.object(["id": "order", "orderNumber": "10042", "amountTotal": 129,
                "orderDateTime": "2026-09-10T10:00:00.000+00:00", "currency": .object(["isoCode": "EUR"]),
                "stateMachineState": .object(["name": "Open", "technicalName": "open"]),
                "orderCustomer": .object(["customerId": "customer", "firstName": "Alexandra", "lastName": "Montgomery-Wellington"])])]
        case "country-state", "custom-field-set", "tag": return []
        default: return []
        }
    }

    private func response(_ json: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: json.encoded()) }

    private func saveCustomer(_ payload: JSONValue) {
        guard let id = payload["id"]?.stringValue, var changes = payload.objectValue else { return }
        var current = entities("customer").first { $0["id"]?.stringValue == id }?.objectValue ?? [:]
        for address in changes.removeValue(forKey: "addresses")?.arrayValue ?? [] {
            guard let addressID = address["id"]?.stringValue, var fields = address.objectValue else { continue }
            var saved = changedAddresses[addressID]?.objectValue ?? (addressID == "address" ? self.address.objectValue : nil) ?? [:]
            fields["customerId"] = .string(id)
            saved.merge(fields, uniquingKeysWith: { _, new in new })
            if saved["countryId"]?.stringValue == "country" { saved["country"] = .object(["id": "country", "name": "Germany"]) }
            changedAddresses[addressID] = .object(saved)
        }
        current.merge(changes, uniquingKeysWith: { _, new in new })
        changedCustomers[id] = .object(current)
    }

    private func value(_ row: JSONValue, field: String) -> JSONValue? {
        field.split(separator: ".").reduce(Optional(row)) { $0?[String($1)] }
    }

    private func matches(_ row: JSONValue, filter: JSONValue) throws -> Bool {
        switch filter["type"]?.stringValue {
        case "equals": return (value(row, field: filter["field"]?.stringValue ?? "") ?? .null) == filter["value"]
        case "multi", "not":
            let results = try (filter["queries"]?.arrayValue ?? []).map { try matches(row, filter: $0) }
            let matches = filter["operator"]?.stringValue == "OR" ? results.contains(true) : results.allSatisfy { $0 }
            return filter["type"]?.stringValue == "not" ? !matches : matches
        default: throw ApiError.network(message: "Unsupported customer UI fixture filter.", underlying: nil)
        }
    }

    private func failOnce(_ flag: String) throws {
        if failures.remove(flag) != nil {
            throw ApiError.network(message: "Fixture request failed. Please retry.", underlying: nil)
        }
    }

    private func requireWriteAccess() throws {
        if readOnly { throw ApiError.unexpected(status: 403, message: "Read-only customer UI fixture.") }
    }

    private func unsupported(_ request: HTTPRequest) -> ApiError {
        ApiError.network(message: "Unimplemented customer UI fixture: \(request.method.rawValue) \(URL(string: request.url)?.path ?? "")", underlying: nil)
    }
}
#endif
