import Foundation

/// Administration's order edit lifecycle. All draft operations carry their own version header.
public struct OrderApi: Sendable {
    let client: ShopwareClient
    public static let liveVersionId = "0fa91ce3e96a4bc2be4bd9ce752c3425"

    public func createVersion(orderId: String, versionId: String) async throws -> String {
        let response = try await client.versionedJSON("/_action/version/order/\(orderId)", versionId: Self.liveVersionId,
                                                     body: .object(["versionId": .string(versionId)]))
        guard response["versionId"]?.stringValue == versionId else {
            throw ApiError.unexpected(status: 200, message: apiLocalized("The order draft response is missing its version. Reload the order before trying again."))
        }
        return versionId
    }

    public func mergeVersion(_ versionId: String) async throws {
        _ = try await client.versionedJSON("/_action/version/merge/order/\(versionId)", versionId: Self.liveVersionId, body: .object([:]))
    }

    public func discardVersion(orderId: String, versionId: String) async throws {
        _ = try await client.versionedJSON("/_action/version/\(versionId)/order/\(orderId)", versionId: Self.liveVersionId, body: .object([:]))
    }

    public func search(_ criteria: Criteria, versionId: String = Self.liveVersionId) async throws -> SearchResult {
        SearchResult.from(try await client.versionedJSON("/search/order", versionId: versionId, body: criteria.toJSON()))
    }

    public func save(orderId: String, payload: JSONValue, versionId: String, removedTagIds: [String] = []) async throws {
        if removedTagIds.isEmpty {
            _ = try await client.versionedJSON("/order/\(orderId)", method: .patch, versionId: versionId, body: payload)
        } else {
            var fields = payload.objectValue ?? [:]
            fields["id"] = .string(orderId)
            let operations: JSONValue = .object([
                "order": .object(["entity": "order", "action": "upsert", "payload": .array([.object(fields)])]),
                "removed-tags": .object(["entity": "order_tag", "action": "delete", "payload": .array(removedTagIds.map {
                    .object(["orderId": .string(orderId), "orderVersionId": .string(versionId), "tagId": .string($0)])
                })]),
            ])
            _ = try await client.versionedJSON("/_action/sync", versionId: versionId, body: operations, singleOperation: true)
        }
    }

    public func removeLineItem(_ id: String, versionId: String) async throws {
        _ = try await client.versionedJSON("/order-line-item/\(id)", method: .delete, versionId: versionId)
    }

    /// The server may return cart errors with HTTP 200; callers must present and inspect them.
    public func recalculate(orderId: String, versionId: String) async throws -> JSONValue {
        try await action(orderId, "recalculate", versionId: versionId)
    }

    public func addProduct(orderId: String, versionId: String, productId: String, quantity: Int) async throws {
        _ = try await action(orderId, "product/\(productId)", versionId: versionId, body: .object(["quantity": .number(Double(quantity))]))
    }

    public func addLineItem(orderId: String, versionId: String, item: JSONValue, credit: Bool) async throws {
        _ = try await action(orderId, credit ? "creditItem" : "lineItem", versionId: versionId, body: item)
    }

    public func addPromotion(orderId: String, versionId: String, code: String) async throws -> JSONValue {
        try await action(orderId, "promotion-item", versionId: versionId, body: .object(["code": .string(code)]))
    }

    public func applyAutomaticPromotions(orderId: String, versionId: String) async throws -> JSONValue {
        do { return try await action(orderId, "applyAutomaticPromotions", versionId: versionId) }
        catch ApiError.notFound {
            // Shopware versions before the dedicated action expose the same behavior via this toggle.
            return try await action(orderId, "toggleAutomaticPromotions", versionId: versionId,
                                    body: .object(["skipAutomaticPromotions": false]))
        }
    }

    private func action(_ orderId: String, _ action: String, versionId: String, body: JSONValue = .object([:])) async throws -> JSONValue {
        try await client.versionedJSON("/_action/order/\(orderId)/\(action)", versionId: versionId, body: body)
    }
}
