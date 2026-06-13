import Testing
@testable import ShopwareAdminAPI

// Fixtures captured from a live Shopware 6.7.8 instance.
struct ApiErrorTests {
    @Test func validationEnvelopeWithTwoErrorsOneNullDetail() {
        let body = """
        {"errors":[
          {"status":"400","code":"FRAMEWORK__INVALID_LIMIT_QUERY","title":"Bad Request",
           "detail":"The limit parameter must be a positive integer greater or equals than 1. Given: abc",
           "source":{"pointer":"/limit"},"meta":{"parameters":{"limit":"abc"}}},
          {"code":"6","status":"400","title":"The user credentials were incorrect.","detail":null}
        ]}
        """
        guard case let .validation(violations) = ApiError.parse(status: 400, body: body) else {
            Issue.record("expected validation"); return
        }
        #expect(violations.count == 2)
        #expect(violations[0].code == "FRAMEWORK__INVALID_LIMIT_QUERY")
        #expect(violations[0].pointer == "/limit")
        #expect(violations[0].detail == "The limit parameter must be a positive integer greater or equals than 1. Given: abc")
        #expect(violations[1].detail == nil)
        #expect(violations[1].title == "The user credentials were incorrect.")
        #expect(ApiError.validation(violations: violations).message == "The limit parameter must be a positive integer greater or equals than 1. Given: abc")
    }

    @Test func oauthErrorShape() {
        let body = #"{"error":"invalid_client","error_description":"Client authentication failed"}"#
        let error = ApiError.parse(status: 401, body: body)
        guard case .auth = error else { Issue.record("expected auth"); return }
        #expect(error.message == "Client authentication failed")
    }

    @Test func authErrorsEnvelope() {
        let body = #"{"errors":[{"code":"9","status":"401","title":"The resource owner or authorization server denied the request.","detail":"The JWT string must have two dots"}]}"#
        let error = ApiError.parse(status: 401, body: body)
        guard case .auth = error else { Issue.record("expected auth"); return }
        #expect(error.message == "The JWT string must have two dots")
    }

    @Test func forbiddenWithMissingPrivilegesInJsonStringDetail() {
        let body = """
        {"errors":[{"code":"FRAMEWORK__MISSING_PRIVILEGE_ERROR","status":"403","title":"Forbidden",
         "detail":"{\\"message\\":\\"Missing privilege\\",\\"missingPrivileges\\":[\\"product_review:update\\"]}"}]}
        """
        guard case let .forbidden(message, privileges) = ApiError.parse(status: 403, body: body) else {
            Issue.record("expected forbidden"); return
        }
        #expect(privileges == ["product_review:update"])
        #expect(message == "Missing privilege")
    }

    @Test func forbiddenWithMissingPrivilegesAsPlainArrayInMeta() {
        let body = """
        {"errors":[{"code":"FRAMEWORK__MISSING_PRIVILEGE_ERROR","status":"403","title":"Forbidden",
         "detail":null,"meta":{"parameters":{"missingPrivileges":["order:read","order:update"]}}}]}
        """
        guard case let .forbidden(message, privileges) = ApiError.parse(status: 403, body: body) else {
            Issue.record("expected forbidden"); return
        }
        #expect(privileges == ["order:read", "order:update"])
        #expect(message == "Forbidden")
    }

    @Test func notFoundEnvelope() {
        let body = #"{"errors":[{"code":"0","status":"404","title":"Not Found","detail":"No route found for POST http:\/\/localhost:8000\/api\/search\/nonexistent-entity"}]}"#
        let error = ApiError.parse(status: 404, body: body)
        guard case .notFound = error else { Issue.record("expected notFound"); return }
        #expect(error.message == "No route found for POST http://localhost:8000/api/search/nonexistent-entity")
    }

    @Test func serverWithHtmlBody() {
        let error = ApiError.parse(status: 500, body: "<html><body><h1>Internal Server Error</h1></body></html>")
        guard case let .server(status, message) = error else { Issue.record("expected server"); return }
        #expect(status == 500)
        #expect(message == "HTTP 500")
    }

    @Test func emptyBodyFallsBackToHttpStatusMessage() {
        let error = ApiError.parse(status: 502, body: "")
        guard case .server(_, let message) = error else { Issue.record("expected server"); return }
        #expect(message == "HTTP 502")

        let nullBody = ApiError.parse(status: 418, body: nil)
        guard case let .unexpected(status, msg) = nullBody else { Issue.record("expected unexpected"); return }
        #expect(status == 418)
        #expect(msg == "HTTP 418")
    }
}
