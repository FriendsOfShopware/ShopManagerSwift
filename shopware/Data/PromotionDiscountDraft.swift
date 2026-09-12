import Foundation
import ShopwareAdminAPI

struct PromotionDiscountDraft: Equatable {
    var scope = "cart"
    var type = "percentage"
    var value = "10"
    var maximum = ""
    init(_ discount: PromotionDiscount? = nil, locale: Locale) {
        if let discount {
            scope = discount.scope; type = discount.type
            value = discount.value.formatted(.number.grouping(.never).precision(.fractionLength(0...16)).locale(locale))
            maximum = discount.maxValue.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...16)).locale(locale)) } ?? ""
        }
    }
    func number(_ text: String, locale: Locale) -> Double? {
        let text = text.trimmed
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) || String($0) == locale.decimalSeparator }) else { return nil }
        guard text.components(separatedBy: locale.decimalSeparator ?? ".").count <= 2 else { return nil }
        guard let number = try? Double(text, format: .number.locale(locale)), number.isFinite else { return nil }
        return number
    }
    func validationError(locale: Locale) -> String? {
        guard let value = number(value, locale: locale), value >= 0 else { return String(localized: "Enter a discount of zero or greater.") }
        if type == "percentage" && value > 100 { return String(localized: "A percentage discount cannot exceed 100%.") }
        if !maximum.trimmed.isEmpty && number(maximum, locale: locale).map({ $0 > 0 }) != true {
            return String(localized: "Enter a positive maximum discount, or leave it empty.")
        }
        return nil
    }
    func payload(locale: Locale, isNew: Bool) -> [String: JSONValue] {
        var payload: [String: JSONValue] = ["value": .number(number(value, locale: locale) ?? 0)]
        if type == "percentage" { payload["maxValue"] = number(maximum, locale: locale).map(JSONValue.number) ?? .null }
        if isNew {
            payload.merge(["scope": .string(scope), "type": .string(type), "considerAdvancedRules": false,
                           "sorterKey": "PRICE_ASC", "applierKey": "ALL", "usageKey": "ALL"]) { _, new in new }
        }
        return payload
    }
}
