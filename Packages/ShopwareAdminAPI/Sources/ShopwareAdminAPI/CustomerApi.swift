import Foundation

/// Customer actions mirror the Administration controllers, including their mail/event behavior.
public struct CustomerApi: Sendable {
    let client: ShopwareClient

    public func permissions() async throws -> AdminPermissions {
        let response = try await client.getJSON("/_info/me")
        guard let user = SwEntity(response).entity("data") else {
            throw ApiError.unexpected(status: 200, message: String(localized: "The shop did not return the current user's permissions.", bundle: .module))
        }
        return AdminPermissions(user: user)
    }

    public func decideGroupRequest(customerIds: [String], accept: Bool, skipMissingRequests: Bool = false) async throws {
        var payload: [String: JSONValue] = ["customerIds": .array(customerIds.map { .string($0) })]
        if skipMissingRequests { payload["silentError"] = .bool(true) }
        try await client.actionPost("/_action/customer-group-registration/\(accept ? "accept" : "decline")", body: .object(payload))
    }

    /// Omitting the password makes Shopware send its password-recovery email.
    public func convertGuest(customerId: String, password: String?) async throws {
        var body: [String: JSONValue] = [:]
        if let password, !password.isEmpty { body["password"] = .string(password) }
        try await client.actionPost("/_action/customer-convert/\(customerId)", body: .object(body))
    }

    public func reserveNumber(salesChannelId: String, preview: Bool = false) async throws -> String {
        let response = try await client.getJSON("/_action/number-range/reserve/customer/\(salesChannelId)?preview=\(preview)")
        guard let number = response["number"]?.stringValue, !number.isEmpty else {
            throw ApiError.unexpected(status: 200, message: String(localized: "The shop did not return a customer number.", bundle: .module))
        }
        return number
    }

    public func imitateToken(customerId: String, salesChannelId: String) async throws -> String {
        let response = try await client.actionPost("/_proxy/generate-imitate-customer-token", body: .object([
            "customerId": .string(customerId), "salesChannelId": .string(salesChannelId),
        ]))
        guard let token = response?["token"]?.stringValue, !token.isEmpty else {
            throw ApiError.unexpected(status: 200, message: String(localized: "The shop did not return a customer login token.", bundle: .module))
        }
        return token
    }

    public func registrationIsBoundToSalesChannel() async throws -> Bool {
        let config = try await client.getJSON("/_action/system-config?domain=core.systemWideLoginRegistration")
        return config["core.systemWideLoginRegistration.isCustomerBoundToSalesChannel"]?.boolValue ?? false
    }

    /// Customer writes and removed tag links are submitted in one sync request.
    public func save(_ customer: JSONValue, removedTagIds: [String] = []) async throws {
        var operations: [String: JSONValue] = [
            "customer": .object(["entity": "customer", "action": "upsert", "payload": .array([customer])]),
        ]
        if !removedTagIds.isEmpty, let id = customer["id"]?.stringValue {
            operations["removed-tags"] = .object([
                "entity": "customer_tag", "action": "delete",
                "payload": .array(removedTagIds.map { .object(["customerId": .string(id), "tagId": .string($0)]) }),
            ])
        }
        try await client.syncOperations(operations)
    }

    public func bulkUpdate(_ customers: [JSONValue]) async throws {
        guard !customers.isEmpty else { return }
        try await client.sync(entity: "customer", payload: customers)
    }

    public func bulkDelete(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await client.sync(entity: "customer", action: "delete", payload: ids.map { .object(["id": .string($0)]) })
    }
}
