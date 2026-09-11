import Foundation
import Testing
@testable import ShopwareAdminAPI

private actor CustomerOrderTransport: HTTPTransport {
    var requests: [HTTPRequest] = []
    let status: Int

    init(status: Int = 200) { self.status = status }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.hasSuffix("/oauth/token") {
            return HTTPResponse(status: 200, body: Data(#"{"access_token":"admin-test","expires_in":600}"#.utf8))
        }
        requests.append(request)
        var response: JSONValue = .object(["token": "cart-token", "lineItems": .array([])])
        if request.url.hasSuffix("switch-customer") { response = .object(["sw-context-token": "assigned-token"]) }
        if request.url.hasSuffix("/context") { response = .object(["contextToken": "updated-token"]) }
        if request.url.contains("/_proxy-order/") { response = .object(["id": "order-id"]) }
        if status != 200 { response = .object(["errors": .array([.object(["detail": "Invalid cart", "code": "CART_ERROR"])])]) }
        return HTTPResponse(status: status, body: response.encoded())
    }
}

struct CustomerOrderApiTests {
    private func service(_ transport: CustomerOrderTransport) -> CustomerOrderApi {
        ShopApi(baseURL: "https://shop.test", auth: .password(username: "test", password: "test", refreshToken: nil), transport: transport).customerOrders
    }

    @Test func customerCartUsesContextTokenHeadersAndCorrectProxyRoutes() async throws {
        let transport = CustomerOrderTransport()
        let api = service(transport)
        let cart = try await api.cart(salesChannelId: "channel")
        #expect(cart["token"] == "cart-token")
        let assigned = try await api.assignCustomer("customer", salesChannelId: "channel", token: "cart-token")
        #expect(assigned == "assigned-token")
        let updated = try await api.updateContext(.object(["shippingAddressId": "address"]), salesChannelId: "channel", token: assigned)
        #expect(updated == "updated-token")
        let requests = await transport.requests
        #expect(requests[0].url == "https://shop.test/api/_proxy/store-api/channel/checkout/cart")
        #expect(requests[0].headers["sw-context-token"] == nil)
        #expect(requests[1].method == .patch)
        #expect(requests[1].headers["sw-context-token"] == "cart-token")
        #expect(JSONValue.parse(try #require(requests[1].body)) == .object([
            "customerId": "customer", "salesChannelId": "channel", "permissions": .array(["allowProductPriceOverwrites"]),
        ]))
        #expect(requests[2].headers["sw-context-token"] == assigned)
        #expect(JSONValue.parse(try #require(requests[2].body)) == .object(["shippingAddressId": "address"]))
        #expect(requests.allSatisfy { !$0.url.contains("token") && $0.headers["Authorization"] == "Bearer admin-test" })
    }

    @Test func itemUpdatesDeletionAndCheckoutHaveDistinctPayloads() async throws {
        let transport = CustomerOrderTransport()
        let api = service(transport)
        _ = try await api.saveItems([.object(["id": "product", "type": "product", "quantity": 1])], salesChannelId: "channel", token: "cart")
        _ = try await api.saveItems([.object(["id": "product", "quantity": 3])], salesChannelId: "channel", token: "cart", updating: true)
        _ = try await api.removeItem("product", salesChannelId: "channel", token: "cart")
        let orderId = try await api.checkout(salesChannelId: "channel", token: "cart", sendMail: false)
        #expect(orderId == "order-id")
        let requests = await transport.requests
        #expect(requests.map(\.method) == [.post, .patch, .delete, .post])
        #expect(JSONValue.parse(try #require(requests[1].body)) == .object(["items": .array([.object(["id": "product", "quantity": 3])])]))
        #expect(JSONValue.parse(try #require(requests[2].body)) == .object(["ids": .array(["product"])]))
        #expect(requests[3].url == "https://shop.test/api/_proxy-order/channel")
        #expect(JSONValue.parse(try #require(requests[3].body)) == .object(["sendOrderConfirmationMail": false]))
    }

    @Test func failedCheckoutSurfacesTheServerFailure() async throws {
        do {
            _ = try await service(CustomerOrderTransport(status: 400)).checkout(salesChannelId: "channel", token: "cart", sendMail: true)
            Issue.record("Checkout must not report success for an invalid cart")
        } catch let error as ApiError {
            #expect(error.message == "Invalid cart")
        }
    }
}
