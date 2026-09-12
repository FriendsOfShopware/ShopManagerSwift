import Foundation

public struct GeneratedDocument: Sendable, Equatable {
    public let id: String
    public let deepLinkCode: String
}

public struct DocumentApi: Sendable {
    let client: ShopwareClient

    public func create(orderId: String, type: String) async throws {
        _ = try await generate(orderId: orderId, type: type)
    }

    /// Document generation reports per-order failures in a successful HTTP response.
    public func generate(orderId: String, type: String, config: JSONValue = .object([:]),
                         referencedDocumentId: String? = nil, staticDocument: Bool = false) async throws -> GeneratedDocument {
        var operation: [String: JSONValue] = ["orderId": .string(orderId), "config": config]
        if let referencedDocumentId { operation["referencedDocumentId"] = .string(referencedDocumentId) }
        if staticDocument { operation["static"] = true }
        let response = try await client.actionPost("/_action/order/document/\(type)/create", body: .array([.object(operation)]))
        if let errors = response?["errors"]?[orderId]?.arrayValue, !errors.isEmpty {
            throw ApiError.parse(status: 400, body: String(data: JSONValue.object(["errors": .array(errors)]).encoded(), encoding: .utf8))
        }
        let documents = response?["data"]?.arrayValue ?? response?["data"]?.objectValue.map { Array($0.values) } ?? []
        guard let document = documents.first, let id = document["documentId"]?.stringValue, !id.isEmpty else {
            throw ApiError.unexpected(status: 200, message: String(localized: "The document response is missing its ID. Refresh the documents before trying again.", bundle: .module))
        }
        return GeneratedDocument(id: id, deepLinkCode: document["documentDeepLink"]?.stringValue ?? "")
    }

    public func upload(documentId: String, data: Data, fileName: String) async throws {
        let name = fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? documentId
        try await client.postBytes("/_action/document/\(documentId)/upload?fileName=\(name)&extension=pdf", bytes: data, mimeType: "application/pdf")
    }

    public func download(documentId: String, deepLinkCode: String) async throws -> Data {
        try await client.getBytes("/_action/document/\(documentId)/\(deepLinkCode)")
    }

    public func preview(orderId: String, deepLinkCode: String, type: String, config: JSONValue, referencedDocumentId: String? = nil) async throws -> Data {
        let json = String(decoding: config.encoded(), as: UTF8.self)
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let reference = referencedDocumentId.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) }.map { "&referencedDocumentId=" + $0 } ?? ""
        return try await client.getBytes("/_action/order/\(orderId)/\(deepLinkCode)/document/\(type)/preview?config=\(encoded)\(reference)")
    }
}
