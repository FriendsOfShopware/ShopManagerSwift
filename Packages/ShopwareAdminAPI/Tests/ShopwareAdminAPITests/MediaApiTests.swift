import Foundation
import Testing
@testable import ShopwareAdminAPI

private actor MediaTransport: HTTPTransport {
    private(set) var requests: [HTTPRequest] = []
    var uploadError: ApiError?
    init(uploadError: ApiError? = nil) { self.uploadError = uploadError }
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.hasSuffix("/oauth/token") { return HTTPResponse(status: 200, body: Data(#"{"access_token":"fixture","expires_in":600}"#.utf8)) }
        requests.append(request)
        if request.url.contains("/upload?"), let uploadError { throw uploadError }
        return HTTPResponse(status: 204, body: Data())
    }
}

struct MediaApiTests {
    private func api(_ transport: MediaTransport) -> MediaApi {
        ShopApi(baseURL: "https://shop.test", auth: .refreshToken(token: "fixture"), transport: transport).media
    }
    @Test func uploadPreservesBinaryMimeNameAndDestination() async throws {
        let transport = MediaTransport()
        let bytes = Data("%PDF-fixture".utf8)
        let id = try await api(transport).upload(bytes: bytes, extension: "pdf", fileName: "Summer & autumn + 50%", mimeType: "application/pdf", mediaFolderId: "folder")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(JSONValue.parse(try #require(requests[0].body)) == .object(["id": .string(id), "mediaFolderId": "folder"]))
        let upload = requests[1]
        #expect(upload.body == bytes)
        #expect(upload.headers["Content-Type"] == "application/pdf")
        let url = try #require(URLComponents(string: upload.url))
        #expect(url.path == "/api/_action/media/\(id)/upload")
        #expect(url.queryItems?.first { $0.name == "fileName" }?.value == "Summer & autumn + 50%")
        #expect(url.queryItems?.first { $0.name == "extension" }?.value == "pdf")
    }
    @Test func renameUsesDedicatedMediaAction() async throws {
        let transport = MediaTransport()
        try await api(transport).rename("media", fileName: "new-name")
        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url == "https://shop.test/api/_action/media/media/rename")
        #expect(JSONValue.parse(try #require(request.body)) == .object(["fileName": "new-name"]))
    }
    @Test func uploadRollbackDistinguishesRejectionFromUnknownOutcome() async {
        for (error, shouldDelete) in [(ApiError.forbidden(message: "Denied", missingPrivileges: []), true), (.network(message: "Response lost", underlying: nil), false)] {
            let transport = MediaTransport(uploadError: error)
            do {
                _ = try await api(transport).upload(bytes: Data([1]), extension: "png", fileName: "test", mimeType: "image/png")
                Issue.record("The upload should fail")
            } catch { }
            #expect(await transport.requests.contains { $0.method == .delete } == shouldDelete)
        }
    }
}
