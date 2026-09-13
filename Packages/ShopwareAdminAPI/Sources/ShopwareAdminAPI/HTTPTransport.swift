import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP request/response model so `ShopwareClient` can be driven by either a real
/// `URLSession` transport or a mock in tests (the Swift analogue of Ktor's `MockEngine`).
public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable {
        case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
    }

    public var method: Method
    public var url: String
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public var bodyText: String { String(decoding: body, as: UTF8.self) }
    public var isSuccess: Bool { (200..<300).contains(status) }
}

public protocol HTTPTransport: Sendable {
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// `URLSession`-backed transport with the timeouts the Android client used (25s request, 10s connect).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 60
            #if !os(Linux)
            config.waitsForConnectivity = false
            #endif
            self.session = URLSession(configuration: config)
        }
    }

    public func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url) else {
            throw ApiError.network(message: "Invalid URL: \(request.url)", underlying: nil)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ApiError.network(message: "Non-HTTP response", underlying: nil)
        }
        return HTTPResponse(status: http.statusCode, body: data)
    }
}
