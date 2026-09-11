#if os(macOS)
import AppKit

/// Launch Services opens URLs with GET, while Shopware requires a login form POST.
/// A short-lived local form lets the browser establish its own storefront session.
@MainActor
enum CustomerBrowserLogin {
    static func open(domain: URL, token: String, customerId: String, userId: String) async throws {
        guard let browser = NSWorkspace.shared.urlForApplication(toOpen: domain) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "customer-login-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let file = directory.appending(path: "login.html")
        do {
            let html = document(domain: domain, token: token, customerId: customerId, userId: userId)
            guard FileManager.default.createFile(atPath: file.path, contents: Data(html.utf8),
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try Task.checkCancellation()
            // Resolve the browser from the storefront URL, not the user's .html file association.
            _ = try await NSWorkspace.shared.open([file], withApplicationAt: browser,
                                                  configuration: NSWorkspace.OpenConfiguration())
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        // Launch completion doesn't mean the browser has read the document yet.
        // Keep cleanup independent of the sheet's lifetime.
        Task {
            try? await Task.sleep(for: .seconds(120))
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func document(domain: URL, token: String, customerId: String, userId: String) -> String {
        let action = domain.appending(path: "account/login/imitate-customer").absoluteString
        let nonce = UUID().uuidString
        let fields = [("token", token), ("customerId", customerId), ("userId", userId)]
            .map { name, value in
                "<input type=\"hidden\" name=\"\(name)\" value=\"\(escape(value))\">"
            }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="\(escape(Bundle.main.preferredLocalizations.first ?? "en"))">
        <head>
          <meta charset="utf-8">
          <meta name="referrer" content="no-referrer">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; base-uri 'none'; form-action http: https:">
          <title>\(escape(String(localized: "Opening storefront")))</title>
        </head>
        <body>
          <p>\(escape(String(localized: "Opening the storefront with the customer's account…")))</p>
          <form method="post" action="\(escape(action))">
            \(fields)
            <noscript><button type="submit">\(escape(String(localized: "Continue to storefront")))</button></noscript>
          </form>
          <script nonce="\(nonce)">document.forms[0].submit();</script>
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
#endif
