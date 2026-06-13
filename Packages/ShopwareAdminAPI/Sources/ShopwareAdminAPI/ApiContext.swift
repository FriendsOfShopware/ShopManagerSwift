import Foundation

public struct ApiContext: Sendable, Equatable {
    public var languageId: String?
    public var inheritance: Bool
    public var currencyId: String?
    public var versionId: String?

    public init(
        languageId: String? = nil,
        inheritance: Bool = true,
        currencyId: String? = nil,
        versionId: String? = nil
    ) {
        self.languageId = languageId
        self.inheritance = inheritance
        self.currencyId = currencyId
        self.versionId = versionId
    }

    public func headers() -> [String: String] {
        var out: [String: String] = [:]
        if let languageId { out["sw-language-id"] = languageId }
        out["sw-inheritance"] = String(inheritance)
        if let currencyId { out["sw-currency-id"] = currencyId }
        if let versionId { out["sw-version-id"] = versionId }
        return out
    }
}
