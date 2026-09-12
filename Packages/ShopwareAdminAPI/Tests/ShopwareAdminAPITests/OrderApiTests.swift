import Foundation
import Testing
@testable import ShopwareAdminAPI

private actor OrderAPITransport: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    var responses: [String: JSONValue]

    init(responses: [String: JSONValue] = [:]) { self.responses = responses }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, body: Data(#"{"access_token":"fixture","expires_in":600}"#.utf8))
        }
        requests.append(request)
        let path = URL(string: request.url)?.path ?? ""
        if let response = responses[path] { return HTTPResponse(status: 200, body: response.encoded()) }
        if path == "/api/_action/version/order/order" {
            return HTTPResponse(status: 200, body: Data(#"{"versionId":"draft-a"}"#.utf8))
        }
        if path == "/api/search/order" {
            return HTTPResponse(status: 200, body: Data(#"{"data":[],"total":0}"#.utf8))
        }
        return HTTPResponse(status: 204, body: Data())
    }
}

struct OrderApiTests {
    private func service(_ transport: OrderAPITransport) -> ShopApi {
        ShopApi(baseURL: "https://shop.test", auth: .password(username: "test", password: "test", refreshToken: nil), transport: transport)
    }

    @Test func documentPreviewCarriesReferenceAndSafelyEncodesSettings() async throws {
        let transport = OrderAPITransport()
        _ = try await service(transport).documents.preview(orderId: "order", deepLinkCode: "link", type: "storno", config: .object(["documentComment": "A&B / C"]), referencedDocumentId: "invoice-id")
        let request = try #require(await transport.requests.first)
        let components = try #require(URLComponents(string: request.url))
        #expect(components.queryItems?.first(where: { $0.name == "referencedDocumentId" })?.value == "invoice-id")
        let json = try #require(components.queryItems?.first(where: { $0.name == "config" })?.value)
        #expect(JSONValue.parse(Data(json.utf8)) == .object(["documentComment": "A&B / C"]))
    }

    @Test func removedTagsUseAtomicSyncWithinOnlyTheirOrderVersion() async throws {
        let transport = OrderAPITransport()
        try await service(transport).orders.save(orderId: "order", payload: .object(["internalComment": "draft"]), versionId: "draft-a", removedTagIds: ["tag"])
        let request = try #require(await transport.requests.first)
        #expect(request.url.hasSuffix("/_action/sync"))
        #expect(request.headers["sw-version-id"] == "draft-a")
        #expect(request.headers["single-operation"] == "1")
        let body = try #require(request.body.flatMap(JSONValue.parse))
        #expect(body["removed-tags"]?["payload"] == .array([.object(["orderId": "order", "orderVersionId": "draft-a", "tagId": "tag"])]))
        #expect(body["order"]?["payload"]?.arrayValue?.first?["id"] == "order")
    }

    @Test func versionLifecycleUsesServerRoutesAndNeverLeaksDraftContext() async throws {
        let transport = OrderAPITransport()
        let api = service(transport)
        #expect(try await api.orders.createVersion(orderId: "order", versionId: "draft-a") == "draft-a")
        async let first: Void = api.orders.save(orderId: "order", payload: .object(["internalComment": "draft"]), versionId: "draft-a")
        async let second: Void = api.orders.save(orderId: "another", payload: .object(["customerComment": "another"]), versionId: "draft-b")
        _ = try await (first, second)
        _ = try await api.orders.search(Criteria().setLimit(1), versionId: "draft-a")
        _ = try await api.repository("order").search(Criteria().setLimit(1))
        try await api.orders.mergeVersion("draft-a")
        try await api.orders.discardVersion(orderId: "another", versionId: "draft-b")
        let requests = await transport.requests
        let save = try #require(requests.first { $0.url.hasSuffix("/order/order") && $0.method == .patch })
        #expect(save.headers["sw-version-id"] == "draft-a")
        #expect(JSONValue.parse(try #require(save.body)) == .object(["internalComment": "draft"]))
        #expect(requests.first { $0.url.hasSuffix("/order/another") }?.headers["sw-version-id"] == "draft-b")
        #expect(requests.filter { $0.url.hasSuffix("/search/order") }.map { $0.headers["sw-version-id"] } == ["draft-a", nil])
        #expect(requests.first?.headers["sw-version-id"] == OrderApi.liveVersionId)
        #expect(requests[requests.count - 2].url == "https://shop.test/api/_action/version/merge/order/draft-a")
        #expect(requests.last?.url == "https://shop.test/api/_action/version/draft-b/order/another")
        #expect(requests.suffix(2).allSatisfy { $0.headers["sw-version-id"] == OrderApi.liveVersionId })
    }

    @Test func draftItemActionsAndRecalculationPreserveServerValidation() async throws {
        let errors: JSONValue = .object(["errors": .object(["stock": .object(["message": "Not enough stock", "blockOrder": true])])])
        let transport = OrderAPITransport(responses: ["/api/_action/order/order/recalculate": errors])
        let api = service(transport).orders
        try await api.addProduct(orderId: "order", versionId: "draft", productId: "product", quantity: 3)
        try await api.removeLineItem("line", versionId: "draft")
        _ = try await api.addPromotion(orderId: "order", versionId: "draft", code: "SUMMER")
        #expect(try await api.recalculate(orderId: "order", versionId: "draft") == errors)
        let requests = await transport.requests
        #expect(requests.map(\.method) == [.post, .delete, .post, .post])
        #expect(requests.allSatisfy { $0.headers["sw-version-id"] == "draft" })
        #expect(JSONValue.parse(try #require(requests[0].body)) == .object(["quantity": 3]))
        #expect(requests[1].url == "https://shop.test/api/order-line-item/line")
        #expect(JSONValue.parse(try #require(requests[2].body)) == .object(["code": "SUMMER"]))
    }

    @Test func documentSettingsAndReferencesReachTheGenerator() async throws {
        let transport = OrderAPITransport(responses: ["/api/_action/order/document/credit_note/create":
            .object(["data": .array([.object(["documentId": "credit", "documentDeepLink": "link"])]), "errors": .array([])])])
        let api = service(transport).documents
        let config: JSONValue = .object(["documentNumber": "C100", "documentDate": "2026-09-11", "custom": .object(["invoiceNumber": "I100"])])
        let result = try await api.generate(orderId: "order", type: "credit_note", config: config, referencedDocumentId: "invoice", staticDocument: true)
        #expect(result.id == "credit")
        #expect(result.deepLinkCode == "link")
        try await api.upload(documentId: result.id, data: Data("%PDF-fixture".utf8), fileName: "Credit & refund")
        let requests = await transport.requests
        #expect(JSONValue.parse(try #require(requests[0].body)) == .array([.object([
            "orderId": "order", "config": config, "referencedDocumentId": "invoice", "static": true,
        ])]))
        #expect(requests[1].url.contains("fileName=Credit%20%26%20refund&extension=pdf"))
        #expect(requests[1].headers["Content-Type"] == "application/pdf")
        #expect(requests[1].body == Data("%PDF-fixture".utf8))
    }

    @Test func documentHTTP200ErrorsAreNotReportedAsSuccess() async throws {
        let transport = OrderAPITransport(responses: ["/api/_action/order/document/invoice/create": .object([
            "data": .array([]), "errors": .object(["order": .array([.object(["detail": "Invoice number already exists", "code": "DOCUMENT_ERROR"])])]),
        ])])
        do {
            try await service(transport).documents.create(orderId: "order", type: "invoice")
            Issue.record("A per-order generation error must be surfaced.")
        } catch let error as ApiError { #expect(error.message == "Invoice number already exists") }
    }

    @Test func missingReceiptsDoNotPretendDraftOrDocumentCreationSucceeded() async throws {
        let transport = OrderAPITransport(responses: ["/api/_action/version/order/order": .object([:]),
                                                     "/api/_action/order/document/invoice/create": .object(["data": .array([])])])
        let api = service(transport)
        await #expect(throws: ApiError.self) { try await api.orders.createVersion(orderId: "order", versionId: "draft-a") }
        await #expect(throws: ApiError.self) { try await api.documents.create(orderId: "order", type: "invoice") }
    }
}
