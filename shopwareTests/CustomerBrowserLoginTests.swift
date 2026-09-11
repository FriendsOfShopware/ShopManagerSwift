#if os(macOS)
import Foundation
import Testing
@testable import shopware

@MainActor
struct CustomerBrowserLoginTests {
    @Test func handoffUsesPOSTAndEscapesUntrustedValues() throws {
        let html = CustomerBrowserLogin.document(
            domain: try #require(URL(string: "https://shop.test/en")),
            token: "\"><script>alert('token')</script>&", customerId: "customer\"id", userId: "user<id")

        #expect(html.contains("method=\"post\" action=\"https://shop.test/en/account/login/imitate-customer\""))
        #expect(html.contains("name=\"token\" value=\"&quot;&gt;&lt;script&gt;alert(&#39;token&#39;)&lt;/script&gt;&amp;\""))
        #expect(html.contains("name=\"customerId\" value=\"customer&quot;id\""))
        #expect(html.contains("name=\"userId\" value=\"user&lt;id\""))
        #expect(!html.contains("<script>alert"))
        #expect(!html.contains("?token="))
        #expect(html.contains("content=\"no-referrer\""))
        #expect(html.contains("document.forms[0].submit()"))
    }
}
#endif
