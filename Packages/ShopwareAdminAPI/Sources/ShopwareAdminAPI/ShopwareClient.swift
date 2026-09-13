import Foundation

public enum PlainAuth: Sendable, Equatable {
    /// Username + password, optionally seeded with a stored refresh token used as the fast path.
    /// When the refresh token is missing or revoked, the client re-grants with the password instead
    /// of ending the session — so a revoked token no longer forces a sign-in-again.
    case password(username: String, password: String, refreshToken: String?)
    case refreshToken(token: String)
}

public enum ShopwareHttp {
    /// Normalizes user input to a base URL without trailing slash or /api suffix.
    public static func normalizeBaseUrl(_ input: String) -> String {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        for suffix in ["/api", "/admin"] {
            if url.hasSuffix(suffix) { url = String(url.dropLast(suffix.count)) }
        }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    /// A Shopware instance answers the token endpoint with a JSON error envelope even for bad requests.
    public static func probeShopware(
        _ baseUrl: String,
        transport: HTTPTransport = URLSessionTransport()
    ) async -> Result<Void, Error> {
        do {
            let body = JSONValue.object(["grant_type": "client_credentials"]).encoded()
            let resp = try await transport.perform(HTTPRequest(
                method: .post,
                url: "\(baseUrl)/api/oauth/token",
                headers: ["Content-Type": "application/json"],
                body: body
            ))
            let text = resp.bodyText
            let looksShopware = text.contains("\"errors\"")
                || text.contains("invalid_")
                || resp.isSuccess
            if !looksShopware {
                return .failure(ApiError.unexpected(
                    status: resp.status,
                    message: "Reachable, but no Shopware Admin API found (HTTP \(resp.status))"
                ))
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

/// Owns the OAuth session: grants, refresh-token rotation (the server revokes the old token on every
/// refresh — the rotated token is awaited into persistence via `onRefreshToken` before first use),
/// refresh-on-401, and `ApiError.authExpired` when the stored refresh token is rejected.
///
/// Modeled as an actor so concurrent callers serialize on the grant the way the Kotlin `grantMutex`
/// did; actor reentrancy collapses a burst of requests onto one in-flight grant.
public actor ShopwareClient {
    public let baseURL: String
    private let auth: PlainAuth
    private let context: ApiContext
    private let transport: HTTPTransport
    private let onRefreshToken: (@Sendable (String) async -> Void)?

    private var accessToken: String?
    private var expiresAt: Date = .distantPast

    public private(set) var currentRefreshToken: String?

    /// Serializes grant() so a refresh-token rotation is never raced (single-use tokens).
    private var grantTask: Task<String, Error>?

    public init(
        baseURL: String,
        auth: PlainAuth,
        context: ApiContext = ApiContext(),
        transport: HTTPTransport = URLSessionTransport(),
        onRefreshToken: (@Sendable (String) async -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.auth = auth
        self.context = context
        self.transport = transport
        self.onRefreshToken = onRefreshToken
        switch auth {
        case let .refreshToken(token):
            self.currentRefreshToken = token
        case let .password(_, _, refreshToken):
            // Seed the stored refresh token so the first request uses the fast path; if it's revoked
            // performGrant() falls through to a password grant.
            if let refreshToken, !refreshToken.isEmpty { self.currentRefreshToken = refreshToken }
        }
    }

    // MARK: - Granting

    private func grant() async throws -> String {
        // Collapse concurrent grants onto one in-flight task (the mutex equivalent).
        if let grantTask {
            return try await grantTask.value
        }
        let task = Task { () throws -> String in
            try await self.performGrant()
        }
        grantTask = task
        defer { grantTask = nil }
        return try await task.value
    }

    private func performGrant() async throws -> String {
        // Another caller may have granted while this one waited.
        if let accessToken, Date() < expiresAt { return accessToken }

        if let refresh = currentRefreshToken, !refresh.isEmpty {
            let resp = try await tokenRequest(.object([
                "grant_type": "refresh_token",
                "client_id": "administration",
                "refresh_token": .string(refresh),
            ]))
            if resp.isSuccess { return try await storeTokens(resp) }
            // 400/401 here means the refresh token is revoked or expired. Anything else
            // (5xx, proxies) is a transient failure and must not end the session.
            if !(400...401).contains(resp.status) {
                throw ApiError.parse(status: resp.status, body: resp.bodyText)
            }
            if case .password = auth {
                // We still hold the password — fall through and re-grant with it (this is what
                // lets a revoked/expired refresh token recover silently, without a sign-in-again).
            } else {
                let parsed = ApiError.parse(status: resp.status, body: resp.bodyText)
                throw ApiError.authExpired(message: parsed.message)
            }
        }

        switch auth {
        case let .password(username, password, _):
            let resp = try await tokenRequest(.object([
                "grant_type": "password",
                "client_id": "administration",
                "scopes": "write",
                "username": .string(username),
                "password": .string(password),
            ]))
            if !resp.isSuccess {
                throw ApiError.parse(status: resp.status, body: resp.bodyText)
            }
            return try await storeTokens(resp)
        case .refreshToken:
            // currentRefreshToken was null or just rejected, and there is nothing to fall back to
            throw ApiError.authExpired(message: "Session expired")
        }
    }

    private func tokenRequest(_ body: JSONValue) async throws -> HTTPResponse {
        try await perform(HTTPRequest(
            method: .post,
            url: "\(baseURL)/api/oauth/token",
            headers: ["Content-Type": "application/json"],
            body: body.encoded()
        ))
    }

    private func storeTokens(_ resp: HTTPResponse) async throws -> String {
        guard let obj = JSONValue.parse(resp.body), let token = obj["access_token"]?.stringValue else {
            throw ApiError.unexpected(status: resp.status, message: "Token response missing access_token")
        }
        let expiresIn = obj["expires_in"]?.intValue
            ?? obj["expires_in"]?.stringValue.flatMap { Int($0) }
            ?? 600
        if let rotated = obj["refresh_token"]?.stringValue, rotated != currentRefreshToken {
            currentRefreshToken = rotated
            await onRefreshToken?(rotated)
        }
        accessToken = token
        expiresAt = Date().addingTimeInterval(Double(expiresIn - 30))
        return token
    }

    private func token() async throws -> String {
        if let accessToken, Date() < expiresAt { return accessToken }
        return try await grant()
    }

    // MARK: - Endpoints

    /// POST /api/search/{entity} in plain-JSON mode.
    public func search(entity: String, criteria: JSONValue) async throws -> JSONValue {
        let resp = try await request { token in
            HTTPRequest(
                method: .post,
                url: "\(self.baseURL)/api/search/\(entity)",
                headers: self.commonHeaders(token, contentType: true),
                body: criteria.encoded()
            )
        }
        return JSONValue.parse(resp.body) ?? .object([:])
    }

    /// GET on an /api path.
    public func getJSON(_ path: String) async throws -> JSONValue {
        let resp = try await request { token in
            HTTPRequest(method: .get, url: "\(self.baseURL)/api\(path)", headers: self.commonHeaders(token))
        }
        return JSONValue.parse(resp.body) ?? .object([:])
    }

    /// POST to an /_action path (state transitions etc.); body defaults to {}.
    @discardableResult
    public func actionPost(_ path: String, body: JSONValue? = nil) async throws -> JSONValue? {
        let resp = try await request { token in
            HTTPRequest(
                method: .post,
                url: "\(self.baseURL)/api\(path)",
                headers: self.commonHeaders(token, contentType: true),
                body: (body ?? .object([:])).encoded()
            )
        }
        return JSONValue.parse(resp.body)
    }

    /// GET binary content (e.g. generated PDF documents).
    public func getBytes(_ path: String) async throws -> Data {
        let resp = try await request { token in
            HTTPRequest(method: .get, url: "\(self.baseURL)/api\(path)", headers: self.commonHeaders(token))
        }
        return resp.body
    }

    /// POST binary content (e.g. media uploads).
    public func postBytes(_ path: String, bytes: Data, mimeType: String) async throws {
        _ = try await request { token in
            var headers = self.commonHeaders(token)
            headers["Content-Type"] = mimeType
            return HTTPRequest(method: .post, url: "\(self.baseURL)/api\(path)", headers: headers, body: bytes)
        }
    }

    public func post(_ path: String, payload: JSONValue) async throws {
        _ = try await request { token in
            HTTPRequest(
                method: .post,
                url: "\(self.baseURL)/api\(path)",
                headers: self.commonHeaders(token, contentType: true),
                body: payload.encoded()
            )
        }
    }

    /// POST /_action/sync — a single upsert operation (insert-or-update by primary key). The
    /// server matches on the payload's `id`, so an existing row is updated and a new one created.
    public func sync(entity: String, action: String = "upsert", payload: [JSONValue]) async throws {
        try await syncOperations([
            "write": .object([
                "entity": .string(entity),
                "action": .string(action),
                "payload": .array(payload),
            ]),
        ])
    }

    /// Sends related writes/deletions together through the DAL's sync transaction.
    public func syncOperations(_ operations: [String: JSONValue]) async throws {
        let body = JSONValue.object(operations)
        _ = try await request { token in
            var headers = self.commonHeaders(token, contentType: true)
            headers["single-operation"] = "1"
            return HTTPRequest(
                method: .post,
                url: "\(self.baseURL)/api/_action/sync",
                headers: headers,
                body: body.encoded()
            )
        }
    }

    public func patch(_ path: String, payload: JSONValue) async throws {
        _ = try await request { token in
            HTTPRequest(
                method: .patch,
                url: "\(self.baseURL)/api\(path)",
                headers: self.commonHeaders(token, contentType: true),
                body: payload.encoded()
            )
        }
    }

    public func delete(_ path: String) async throws {
        _ = try await request { token in
            HTTPRequest(method: .delete, url: "\(self.baseURL)/api\(path)", headers: self.commonHeaders(token))
        }
    }

    // MARK: - Request plumbing

    /// Version context belongs to an individual draft request, never to the shared shop client.
    func versionedJSON(_ path: String, method: HTTPRequest.Method = .post,
                       versionId: String, body: JSONValue? = nil, singleOperation: Bool = false) async throws -> JSONValue {
        let response = try await request { token in
            var headers = self.commonHeaders(token, contentType: body != nil)
            headers["sw-version-id"] = versionId
            if singleOperation { headers["single-operation"] = "1" }
            return HTTPRequest(method: method, url: "\(self.baseURL)/api\(path)", headers: headers, body: body?.encoded())
        }
        if response.body.isEmpty { return .object([:]) }
        guard let result = JSONValue.parse(response.body) else {
            throw ApiError.unexpected(status: response.status, message: apiLocalized("The server returned an invalid JSON response."))
        }
        return result
    }

    /// Authenticated JSON request used by cart proxy endpoints. Context tokens stay in headers.
    func contextualJSON(_ path: String, method: HTTPRequest.Method = .get,
                        contextToken: String? = nil, body: JSONValue? = nil) async throws -> JSONValue {
        let response = try await request { token in
            var headers = self.commonHeaders(token, contentType: body != nil)
            if let contextToken { headers["sw-context-token"] = contextToken }
            return HTTPRequest(method: method, url: "\(self.baseURL)/api\(path)", headers: headers, body: body?.encoded())
        }
        guard let result = JSONValue.parse(response.body) else {
            if method == .delete, response.body.isEmpty { return .object([:]) }
            throw ApiError.unexpected(status: response.status, message: "The server returned an invalid JSON response.")
        }
        return result
    }

    /// Retries once with a fresh grant on 401; any non-2xx becomes an ApiError.
    private func request(_ build: (String) -> HTTPRequest) async throws -> HTTPResponse {
        var resp = try await perform(build(try await token()))
        if resp.status == 401 {
            accessToken = nil // the cached token was rejected regardless of its local expiry
            resp = try await perform(build(try await token()))
        }
        if !resp.isSuccess {
            throw ApiError.parse(status: resp.status, body: resp.bodyText)
        }
        return resp
    }

    private func commonHeaders(_ token: String, contentType: Bool = false) -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
        ]
        if contentType { headers["Content-Type"] = "application/json" }
        for (name, value) in context.headers() { headers[name] = value }
        return headers
    }

    private func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.perform(request)
        } catch let error as ApiError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ApiError.networkError(error)
        }
    }
}
