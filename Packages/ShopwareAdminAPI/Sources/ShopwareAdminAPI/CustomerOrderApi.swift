import Foundation

/// Uses the same sales-channel cart and checkout routes as Administration's order creation.
public struct CustomerOrderApi: Sendable {
    let client: ShopwareClient

    public func cart(salesChannelId: String, token: String? = nil) async throws -> JSONValue {
        try await client.contextualJSON(path(salesChannelId, "checkout/cart"), contextToken: token)
    }

    public func assignCustomer(_ customerId: String, salesChannelId: String, token: String) async throws -> String {
        let result = try await client.contextualJSON("/_proxy/switch-customer", method: .patch, contextToken: token,
                                                    body: .object(["customerId": .string(customerId),
                                                                   "salesChannelId": .string(salesChannelId),
                                                                   "permissions": .array(["allowProductPriceOverwrites"])]))
        guard let token = result["sw-context-token"]?.stringValue, !token.isEmpty else {
            throw ApiError.unexpected(status: 200, message: String(localized: "Customer context response is missing its token.", bundle: .module))
        }
        return token
    }

    public func context(salesChannelId: String, token: String) async throws -> JSONValue {
        try await client.contextualJSON(path(salesChannelId, "context"), contextToken: token)
    }

    public func updateContext(_ values: JSONValue, salesChannelId: String, token: String) async throws -> String {
        let result = try await client.contextualJSON(path(salesChannelId, "context"), method: .patch, contextToken: token, body: values)
        return result["contextToken"]?.stringValue ?? result["sw-context-token"]?.stringValue ?? token
    }

    public func saveItems(_ items: [JSONValue], salesChannelId: String, token: String, updating: Bool = false) async throws -> JSONValue {
        try await client.contextualJSON(path(salesChannelId, "checkout/cart/line-item"), method: updating ? .patch : .post,
                                        contextToken: token, body: .object(["items": .array(items)]))
    }

    public func removeItem(_ id: String, salesChannelId: String, token: String) async throws -> JSONValue {
        try await client.contextualJSON(path(salesChannelId, "checkout/cart/line-item"), method: .delete,
                                        contextToken: token, body: .object(["ids": .array([.string(id)])]))
    }

    public func checkout(salesChannelId: String, token: String, sendMail: Bool) async throws -> String {
        let result = try await client.contextualJSON("/_proxy-order/\(salesChannelId)", method: .post,
                                                    contextToken: token, body: .object(["sendOrderConfirmationMail": .bool(sendMail)]))
        guard let id = result["id"]?.stringValue, !id.isEmpty else {
            throw ApiError.unexpected(status: 200, message: String(localized: "Order response is missing its ID. Check the order history before trying again.", bundle: .module))
        }
        return id
    }

    public func cancel(salesChannelId: String, token: String) async throws {
        _ = try await client.contextualJSON(path(salesChannelId, "checkout/cart"), method: .delete, contextToken: token)
    }

    private func path(_ salesChannelId: String, _ route: String) -> String {
        "/_proxy/store-api/\(salesChannelId)/\(route)"
    }
}
