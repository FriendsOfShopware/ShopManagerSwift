import Foundation
import Testing
@testable import ShopwareAdminAPI

private actor CustomerTransport: HTTPTransport {
    var requests: [HTTPRequest] = []
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, body: Data(#"{"access_token":"test","expires_in":600}"#.utf8))
        }
        requests.append(request)
        if request.url.hasSuffix("/_info/me") {
            return HTTPResponse(status: 200, body: Data(#"{"data":{"admin":false,"aclRoles":[{"privileges":["customer:read","customer:update"]}]}}"#.utf8))
        }
        return HTTPResponse(status: 204, body: Data())
    }
}

struct CustomerApiTests {
    private func api(_ transport: CustomerTransport) -> CustomerApi {
        ShopApi(baseURL: "https://shop.test", auth: .password(username: "test", password: "test", refreshToken: nil), transport: transport).customers
    }

    @Test func permissionsDenyUnlistedWritesAndHonorAdministrator() async throws {
        let permissions = try await api(CustomerTransport()).permissions()
        #expect(permissions.allows("customer:read"))
        #expect(permissions.allows("customer:update"))
        #expect(!permissions.allows("customer:delete"))
        #expect(!AdminPermissions().allows("customer:update"))
        #expect(AdminPermissions(isAdmin: true).allows("customer:delete"))
    }

    @Test func customerAndRemovedTagLinksShareOneSyncRequest() async throws {
        let transport = CustomerTransport()
        try await api(transport).save(.object(["id": "c", "firstName": "Ada"]), removedTagIds: ["tag"])
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url == "https://shop.test/api/_action/sync")
        let payload = JSONValue.parse(try #require(request.body))
        #expect(payload?["customer"]?["payload"] == .array([.object(["id": "c", "firstName": "Ada"])]))
        #expect(payload?["removed-tags"]?["entity"] == "customer_tag")
        #expect(payload?["removed-tags"]?["action"] == "delete")
        #expect(payload?["removed-tags"]?["payload"] == .array([.object(["customerId": "c", "tagId": "tag"])]))
    }

    @Test func groupRequestAndConversionUseDedicatedControllers() async throws {
        let transport = CustomerTransport()
        let service = api(transport)
        try await service.decideGroupRequest(customerIds: ["c"], accept: true)
        try await service.convertGuest(customerId: "c", password: "secret")
        let requests = await transport.requests
        #expect(requests[0].url.hasSuffix("/_action/customer-group-registration/accept"))
        #expect(JSONValue.parse(try #require(requests[0].body)) == .object(["customerIds": .array(["c"])]))
        #expect(requests[1].url.hasSuffix("/_action/customer-convert/c"))
        #expect(JSONValue.parse(try #require(requests[1].body)) == .object(["password": "secret"]))
    }
}
