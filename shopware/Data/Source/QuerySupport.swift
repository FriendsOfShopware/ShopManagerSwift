import Foundation
import ShopwareAdminAPI

// Shared helpers used across the query extensions.

extension Date {
    /// Epoch milliseconds — the unit the persisted/model layer uses (mirrors Instant.toEpochMilli()).
    var epochMs: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}

/// Composes a multi-line postal address from an address entity, dropping blank lines.
func formatAddress(_ a: SwEntity) -> String? {
    let lines = [
        [a.string("firstName"), a.string("lastName")].compactMap { $0 }.joined(separator: " "),
        a.string("street") ?? "",
        [a.string("zipcode"), a.string("city")].compactMap { $0 }.joined(separator: " "),
        a.entity("country")?.translated("name") ?? "",
    ].filter { !$0.isEmpty }
    let joined = lines.joined(separator: "\n")
    return joined.isEmpty ? nil : joined
}

/// media.url carries the shop's configured public host (APP_URL), which can differ from the URL
/// the app connects through (internal vs external hostnames). Swap scheme+authority for the
/// connected base URL.
func rebaseMediaUrl(_ url: String, _ shopBaseUrl: String) -> String {
    guard url.hasPrefix("http"), let schemeRange = url.range(of: "://") else { return url }
    let afterScheme = schemeRange.upperBound
    guard let slashIndex = url[afterScheme...].firstIndex(of: "/") else { return url }
    var base = shopBaseUrl
    while base.hasSuffix("/") { base.removeLast() }
    return base + url[slashIndex...]
}

/// First entry of a product's `price` array (the default currency's price object).
func firstPriceObject(_ entity: SwEntity) -> [String: JSONValue]? {
    guard case let .array(prices)? = entity.json["price"], let first = prices.first,
          case let .object(o) = first else { return nil }
    return o
}

func priceArray(_ entity: SwEntity) -> JSONValue? {
    if case .array? = entity.json["price"] { return entity.json["price"] }
    return nil
}

/// JSON null for a blank optional, trimmed string otherwise — so the server clears the field.
func nullableField(_ value: String?) -> JSONValue {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty { return .string(trimmed) }
    return .null
}
