import Foundation
import ShopwareAdminAPI

// Live product info for the quick-action sheet — fetched on demand, not persisted.
struct ProductQuickInfo: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var productNumber: String
    var stock: Int
    var active: Bool
    var grossPrice: Double?
    var netPrice: Double?
    var priceLinked: Bool = true
    var taxRate: Double?
    /// false for variant children / advanced (rule) prices
    var priceEditable: Bool
    var rawPrice: JSONValue?
}

/// A row in the products listing — fetched live through the listing pager.
struct ProductRow: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var productNumber: String
    var active: Bool
    var stock: Int
    var grossPrice: Double?
    var manufacturer: String?
    /// rebased onto the shop's base URL
    var coverUrl: String?
}

/// Rich product detail — fetched on demand for the detail screen, not persisted.
struct ProductDetail: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var productNumber: String
    var description: String?
    var active: Bool
    var stock: Int
    var availableStock: Int
    var grossPrice: Double?
    var netPrice: Double?
    /// whether gross/net are kept in sync via the tax rate (admin's linked price)
    var priceLinked: Bool = true
    /// false for advanced (rule) prices
    var priceEditable: Bool
    var rawPrice: JSONValue?
    var taxRate: Double?
    var ean: String?
    var manufacturerNumber: String?
    var manufacturer: String?
    var categories: [String]
    /// sales channels this product is visible in
    var salesChannels: [String]
    var coverUrl: String?
    /// all product media, rebased
    var galleryUrls: [String]
    var ratingAverage: Double?
    var childCount: Int
    var releaseDateMs: Int64?
}

/// A variant child of a configurable product — editable stock/price.
struct ProductVariant: Equatable, Identifiable, Sendable {
    var id: String
    var productNumber: String
    /// e.g. ["Blue", "M"]
    var optionLabels: [String]
    var active: Bool
    var stock: Int
    var grossPrice: Double?
    var netPrice: Double?
    var priceLinked: Bool = true
    /// own tax rate, or the parent's when the variant inherits it
    var taxRate: Double?
    var priceEditable: Bool
    var rawPrice: JSONValue?
}

/// A validated gross/net/linked price change (mirrors the admin's sw-price-field output).
struct PriceEdit: Equatable, Sendable {
    var gross: Double
    var net: Double
    var linked: Bool
}
