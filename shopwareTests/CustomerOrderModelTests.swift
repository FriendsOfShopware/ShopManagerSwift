import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

private actor CustomerOrderModelTransport: HTTPTransport {
    private(set) var checkoutAttempts = 0
    private(set) var canceledCarts = 0
    var failContextChange = false

    func setFailContextChange(_ value: Bool) { failContextChange = value }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.hasSuffix("/oauth/token") { return response(.object(["access_token": "test", "expires_in": 600])) }
        if request.url.contains("/_proxy-order/") {
            checkoutAttempts += 1
            throw ApiError.network(message: "Connection lost after checkout", underlying: nil)
        }
        if request.url.hasSuffix("switch-customer") { return response(.object(["sw-context-token": "assigned"])) }
        if request.url.contains("/search/") { return response(.object(["total": 0, "data": .array([])])) }
        if request.url.hasSuffix("/context") {
            if request.method == .patch {
                if failContextChange { throw ApiError.server(status: 500, message: "Context update failed") }
                return response(.object(["contextToken": "assigned"]))
            }
            return response(.object(["currency": .object(["id": "currency", "isoCode": "USD"])]))
        }
        if request.method == .delete { canceledCarts += 1 }
        return response(.object([
            "token": "new-cart", "lineItems": .array([.object(["id": "product", "quantity": 1])]),
            "price": .object(["totalPrice": 50]), "errors": .object([:]),
        ]))
    }

    private func response(_ value: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: value.encoded()) }
}

@MainActor
struct CustomerOrderModelTests {
    private func model(transport: CustomerOrderModelTransport) -> CustomerOrderCreateModel {
        let api = ShopApi(baseURL: "https://shop.test", auth: .password(username: "test", password: "test", refreshToken: nil), transport: transport)
        let customer = parseCustomerDetail(SwEntity(.object(["id": "customer", "salesChannelId": "channel"])))
        return CustomerOrderCreateModel(api: api, customer: customer)
    }

    @Test func unknownCheckoutOutcomePreventsRepeatedCreationAndCartDeletion() async {
        let transport = CustomerOrderModelTransport()
        let model = model(transport: transport)
        await model.start()
        #expect(model.canCreate)
        #expect(model.currencyIso == "USD")
        #expect(await model.create() == nil)
        #expect(model.checkoutUncertain)
        #expect(!model.canCreate)
        #expect(await model.create() == nil)
        #expect(await transport.checkoutAttempts == 1)
        #expect(await model.cancel())
        #expect(await transport.canceledCarts == 0)
    }

    @Test func failedContextUpdateRequiresFreshCartBeforeCheckout() async {
        let transport = CustomerOrderModelTransport()
        let model = model(transport: transport)
        await model.start()
        #expect(model.canCreate)
        await transport.setFailContextChange(true)
        await model.changeContext(field: "shippingMethodId", id: "shipping")
        #expect(model.error != nil)
        #expect(!model.canCreate)
        await model.reloadCart()
        #expect(model.error == nil)
        #expect(model.canCreate)
        #expect(await model.cancel())
        #expect(await transport.canceledCarts == 1)
    }
}
