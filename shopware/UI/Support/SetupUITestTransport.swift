#if DEBUG
import Foundation
import ShopwareAdminAPI

/// Exercises the real setup API client without contacting a shop or writing credentials to Keychain.
actor SetupUITestTransport: HTTPTransport {
    private var failures: Set<String>
    private let deniedEntities: Set<String>
    private(set) var grants = 0

    init(arguments: [String] = [], deniedEntities: Set<String> = []) {
        failures = Set(arguments)
        self.deniedEntities = deniedEntities
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "setup-ui.test" else {
            throw ApiError.unexpected(status: 400, message: "Unexpected setup fixture host")
        }
        let payload = request.body.flatMap(JSONValue.parse)
        if url.path == "/api/oauth/token" {
            if payload?["grant_type"] == "client_credentials" {
                if failures.remove("--setup-fail-url-once") != nil { throw URLError(.notConnectedToInternet) }
                return response(.object(["errors": .array([])]), status: 400)
            }
            guard payload?["grant_type"] == "password" else {
                throw ApiError.unexpected(status: 400, message: "Unexpected setup grant")
            }
            grants += 1
            if failures.remove("--setup-fail-login-once") != nil {
                return response(.object(["errors": .array([.object(["detail": "Invalid credentials"])])]), status: 401)
            }
            return response(.object(["access_token": "setup-access", "refresh_token": "setup-refresh", "expires_in": 3600]))
        }
        guard request.headers["Authorization"] == "Bearer setup-access" else {
            throw ApiError.auth(message: "Setup fixture requires authentication")
        }
        if url.path == "/api/_info/version" { return response(.object(["version": "6.7.14.0"])) }
        if url.path.hasPrefix("/api/search/"), request.method == .post {
            let entity = url.lastPathComponent
            if deniedEntities.contains(entity.replacingOccurrences(of: "-", with: "_")) {
                return response(.object(["errors": .array([])]), status: 403)
            }
            let rows: [JSONValue]
            switch entity {
            case "order", "product", "customer", "promotion", "product-review", "media": rows = []
            case "currency": rows = [.object(["id": "currency", "isoCode": "EUR", "factor": 1])]
            case "sales-channel": rows = [.object(["id": "channel", "name": "Meadow Studio"])]
            case "language": rows = [
                .object(["id": "2fbb5fe2e29a4d70aa5854ce7ce3e20b", "name": "English", "locale": .object(["code": "en-GB"])]),
                .object(["id": "de", "name": "Deutsch", "locale": .object(["code": "de-DE"])])
            ]
            default: throw ApiError.unexpected(status: 400, message: "Unexpected setup fixture search: \(entity)")
            }
            return response(.object(["data": .array(rows), "total": .int(rows.count)]))
        }
        throw ApiError.unexpected(status: 400, message: "Unexpected setup fixture route: \(url.path)")
    }

    private func response(_ body: JSONValue, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: body.encoded())
    }
}
#endif
