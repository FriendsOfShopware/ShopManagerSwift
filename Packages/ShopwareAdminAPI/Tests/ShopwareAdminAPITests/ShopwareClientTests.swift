import Foundation
import Testing
@testable import ShopwareAdminAPI

// Mirrors the live 6.7.8 token endpoint: password and refresh grants both return a rotating
// refresh_token; a used refresh token is revoked (400, errors envelope).
private actor FakeTokenServer {
    var accessCounter = 0
    var refreshCounter = 0
    var validRefreshTokens: Set<String> = []
    var grantLog: [String] = []
    var expiresIn = 600

    func seed(_ token: String) { validRefreshTokens.insert(token) }
    func clearRefreshTokens() { validRefreshTokens.removeAll() }
    func setExpiresIn(_ value: Int) { expiresIn = value }
    func log() -> [String] { grantLog }
    func isValid(_ token: String) -> Bool { validRefreshTokens.contains(token) }

    func handle(_ body: String) -> (status: Int, body: String) {
        let grantType = firstMatch(#""grant_type":"(\w+)""#, in: body)
        grantLog.append(grantType ?? "?")
        switch grantType {
        case "password":
            if body.contains("\"password\":\"correct\"") {
                return (200, issue())
            }
            return (400, #"{"errors":[{"code":"6","status":"400","title":"The user credentials were incorrect."}]}"#)
        case "refresh_token":
            let token = firstMatch(#""refresh_token":"([^"]+)""#, in: body)
            if let token, validRefreshTokens.remove(token) != nil {
                return (200, issue())
            }
            return (400, #"{"errors":[{"code":"8","status":"400","title":"The refresh token is invalid.","detail":"Token has been revoked"}]}"#)
        default:
            return (400, #"{"errors":[{"title":"unsupported grant"}]}"#)
        }
    }

    private func issue() -> String {
        let access = "access-\(accessCounter)"; accessCounter += 1
        let refresh = "refresh-\(refreshCounter)"; refreshCounter += 1
        validRefreshTokens.insert(refresh)
        return #"{"token_type":"Bearer","expires_in":\#(expiresIn),"access_token":"\#(access)","refresh_token":"\#(refresh)"}"#
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// Routes /oauth/token to the fake server and everything else to an api handler.
private struct MockTransport: HTTPTransport {
    let server: FakeTokenServer
    let api: @Sendable (HTTPRequest) -> (status: Int, body: String)

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.hasSuffix("/oauth/token") {
            let text = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let (status, body) = await server.handle(text)
            return HTTPResponse(status: status, body: Data(body.utf8))
        }
        let (status, body) = api(request)
        return HTTPResponse(status: status, body: Data(body.utf8))
    }
}

struct ShopwareClientTests {
    private func client(
        _ server: FakeTokenServer,
        auth: PlainAuth,
        onRefreshToken: (@Sendable (String) async -> Void)? = nil,
        api: @escaping @Sendable (HTTPRequest) -> (status: Int, body: String) = { _ in (200, "{}") }
    ) -> ShopwareClient {
        ShopwareClient(
            baseURL: "https://shop.test",
            auth: auth,
            transport: MockTransport(server: server, api: api),
            onRefreshToken: onRefreshToken
        )
    }

    @Test func passwordGrantStoresAndReportsRefreshToken() async throws {
        let server = FakeTokenServer()
        let reported = Box<String?>(nil)
        let c = client(server, auth: .password(username: "admin", password: "correct")) { token in
            await reported.set(token)
        }

        _ = try await c.getJSON("/test")

        #expect(await server.log() == ["password"])
        #expect(await reported.get() == "refresh-0")
        #expect(await c.currentRefreshToken == "refresh-0")
    }

    @Test func refreshGrantRotatesAndPersistsBeforeUse() async throws {
        let server = FakeTokenServer()
        await server.seed("seed")
        let rotations = Box<[String]>([])
        let c = client(server, auth: .refreshToken(token: "seed")) { token in
            await rotations.append(token)
        }

        _ = try await c.getJSON("/test")

        #expect(await server.log() == ["refresh_token"])
        #expect(await rotations.get() == ["refresh-0"])
        #expect(await c.currentRefreshToken == "refresh-0")
        #expect(await server.isValid("seed") == false)
    }

    @Test func expiredAccessTokenTriggersRefreshGrant() async throws {
        let server = FakeTokenServer()
        await server.setExpiresIn(0) // with the 30s safety margin every call re-grants
        await server.seed("seed")
        let c = client(server, auth: .refreshToken(token: "seed"))

        _ = try await c.getJSON("/one")
        _ = try await c.getJSON("/two")

        #expect(await server.log() == ["refresh_token", "refresh_token"])
        #expect(await c.currentRefreshToken == "refresh-1")
    }

    @Test func revokedRefreshTokenThrowsAuthExpired() async throws {
        let server = FakeTokenServer() // "stale" was never valid → revoked
        let c = client(server, auth: .refreshToken(token: "stale"))

        await #expect(throws: ApiError.self) {
            _ = try await c.getJSON("/test")
        }
        do {
            _ = try await c.getJSON("/test")
        } catch let ApiError.authExpired(message) {
            #expect(message.contains("revoked") || message.contains("invalid"))
        } catch {
            Issue.record("expected authExpired, got \(error)")
        }
    }

    @Test func blankRefreshTokenThrowsAuthExpiredWithoutServerCall() async throws {
        let server = FakeTokenServer()
        let c = client(server, auth: .refreshToken(token: ""))

        do {
            _ = try await c.getJSON("/test")
            Issue.record("expected authExpired")
        } catch ApiError.authExpired {
            #expect(await server.log().isEmpty)
        }
    }

    @Test func revokedRefreshFallsBackToPasswordDuringConnect() async throws {
        let server = FakeTokenServer()
        await server.setExpiresIn(0)
        let c = client(server, auth: .password(username: "admin", password: "correct"))

        _ = try await c.getJSON("/one") // password grant → refresh-0
        await server.clearRefreshTokens() // simulate server-side revocation
        _ = try await c.getJSON("/two") // refresh fails → falls back to password

        #expect(await server.log() == ["password", "refresh_token", "password"])
    }

    @Test func badPasswordSurfacesAsValidationNotAuthExpired() async throws {
        let server = FakeTokenServer()
        let c = client(server, auth: .password(username: "admin", password: "wrong"))

        do {
            _ = try await c.getJSON("/test")
            Issue.record("expected validation")
        } catch let ApiError.validation(violations) {
            let msg = ApiError.validation(violations: violations).message
            #expect(msg.contains("incorrect"))
        }
    }

    @Test func rejected401RetriesOnceWithFreshGrant() async throws {
        let server = FakeTokenServer()
        await server.seed("seed")
        let calls = Box<Int>(0)
        // first business call is rejected even though the token is locally unexpired
        let c = client(server, auth: .refreshToken(token: "seed"), api: { _ in
            let n = calls.incrementSync()
            return n == 1 ? (401, "{}") : (200, #"{"ok":true}"#)
        })

        let result = try await c.getJSON("/test")

        #expect(calls.getSync() == 2)
        #expect(await server.log() == ["refresh_token", "refresh_token"])
        #expect(result["ok"]?.stringValue == "true" || result["ok"]?.boolValue == true)
    }

    @Test func concurrentRequestsShareOneGrant() async throws {
        let server = FakeTokenServer()
        await server.seed("seed")
        let c = client(server, auth: .refreshToken(token: "seed"))

        await withTaskGroup(of: Void.self) { group in
            for i in 1...8 {
                group.addTask { _ = try? await c.getJSON("/p\(i)") }
            }
        }

        // single-use rotation would make a second concurrent grant fail hard —
        // the actor must collapse them into one
        #expect(await server.log() == ["refresh_token"])
    }
}

/// Tiny thread-safe box for capturing values from sendable closures in tests.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func set(_ newValue: T) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func getSync() -> T { get() }
}

extension Box where T == [String] {
    func append(_ element: String) { lock.lock(); value.append(element); lock.unlock() }
}

extension Box where T == Int {
    func incrementSync() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
