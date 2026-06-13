import Foundation

public struct EntityRepository: Sendable {
    private let client: ShopwareClient
    /// The API routes entities kebab-cased (product_review -> /api/product-review).
    public let entityName: String

    public init(client: ShopwareClient, entityName: String) {
        self.client = client
        self.entityName = entityName.replacingOccurrences(of: "_", with: "-")
    }

    public func search(_ criteria: Criteria) async throws -> SearchResult {
        SearchResult.from(try await client.search(entity: entityName, criteria: criteria.toJSON()))
    }

    /// Does not mutate the passed criteria; ids are added to the emitted payload only.
    public func get(_ id: String, criteria: Criteria = Criteria()) async throws -> SwEntity? {
        var payload = criteria.toJSON().objectValue ?? [:]
        payload["ids"] = .array([.string(id)])
        let result = SearchResult.from(try await client.search(entity: entityName, criteria: .object(payload)))
        return result.data.first
    }

    public func create(_ payload: JSONValue) async throws {
        try await client.post("/\(entityName)", payload: payload)
    }

    public func patch(_ id: String, _ payload: JSONValue) async throws {
        try await client.patch("/\(entityName)/\(id)", payload: payload)
    }

    public func delete(_ id: String) async throws {
        try await client.delete("/\(entityName)/\(id)")
    }
}
