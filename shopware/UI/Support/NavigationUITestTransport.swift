#if DEBUG
import Foundation
import ShopwareAdminAPI

/// Compose existing fixtures behind the production app shell, without a network fallback.
actor NavigationUITestTransport: HTTPTransport {
    private let orders = OrderUITestTransport()
    private let customers = CustomerUITestTransport(arguments: [])
    private let media = MediaUITestTransport()

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard var url = URLComponents(string: request.url), url.host == "navigation-ui.test" else {
            throw ApiError.network(message: "Navigation fixtures reject non-fixture hosts.", underlying: nil)
        }
        var copy = request
        if url.path.contains("/search/media") {
            url.host = "media-ui.test"
            copy.url = url.string!
            return try await media.perform(copy)
        }
        if url.path.contains("/search/customer") {
            url.host = "customer-ui.test"
            copy.url = url.string!
            return try await customers.perform(copy)
        }
        url.host = "order-ui.test"
        copy.url = url.string!
        return try await orders.perform(copy)
    }
}
#endif
