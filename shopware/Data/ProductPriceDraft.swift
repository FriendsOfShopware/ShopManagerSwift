import Foundation
import ShopwareAdminAPI

struct ProductPriceDraft: Equatable {
    let currencyID: String
    var gross: String
    var net: String
    var linked: Bool
    init(price: JSONValue?, currencyID: String = ShopwareDefaults.currencyID, locale: Locale) {
        self.currencyID = currencyID
        gross = ProductNumberInput.text(price?["gross"]?.doubleValue, locale: locale)
        net = ProductNumberInput.text(price?["net"]?.doubleValue, locale: locale)
        linked = price?["linked"]?.boolValue ?? true
    }
    mutating func updateGross(_ value: String, taxRate: Double?, locale: Locale) {
        gross = value
        if linked, let taxRate, let value = ProductNumberInput.decimal(value, locale: locale) {
            net = ProductNumberInput.text(value / (1 + taxRate / 100), locale: locale)
        }
    }
    mutating func updateNet(_ value: String, taxRate: Double?, locale: Locale) {
        net = value
        if linked, let taxRate, let value = ProductNumberInput.decimal(value, locale: locale) {
            gross = ProductNumberInput.text(value * (1 + taxRate / 100), locale: locale)
        }
    }
    func validationError(locale: Locale) -> String? {
        guard ProductNumberInput.decimal(gross, locale: locale) != nil, ProductNumberInput.decimal(net, locale: locale) != nil else {
            return String(localized: "Enter valid gross and net prices of zero or greater.")
        }
        return nil
    }
    /// Match by currency ID. Keep list prices, regulation prices, extensions, and
    /// all other currencies intact, including when the API changes array order.
    func prices(replacing original: [JSONValue], locale: Locale) -> [JSONValue]? {
        guard let gross = ProductNumberInput.decimal(gross, locale: locale), let net = ProductNumberInput.decimal(net, locale: locale) else { return nil }
        var rows = original
        let index = rows.firstIndex { $0["currencyId"]?.stringValue == currencyID }
        var value = index.flatMap { rows[$0].objectValue } ?? [:]
        value.merge(["currencyId": .string(currencyID), "gross": .number(gross), "net": .number(net), "linked": .bool(linked)]) { _, new in new }
        if let index { rows[index] = .object(value) } else { rows.append(.object(value)) }
        return rows
    }
}
