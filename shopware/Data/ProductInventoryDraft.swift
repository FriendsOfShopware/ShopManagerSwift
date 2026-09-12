import Foundation
import ShopwareAdminAPI

struct ProductInventoryDraft: Equatable {
    var numbers: [ProductInventoryField: String]
    var closeout: Bool
    var shippingFree: Bool
    var deliveryTimeID: String
    var unitID: String
    var packUnit: String
    var packUnitPlural: String
    var releaseDate: Date?
    subscript(field: ProductInventoryField) -> String {
        get { numbers[field, default: ""] }
        set { numbers[field] = newValue }
    }
    init(_ product: ProductItem, locale: Locale) {
        numbers = Dictionary(uniqueKeysWithValues: ProductInventoryField.allCases.map { field in
            let fallback: Double? = field == .stock ? 0 : [.minPurchase, .purchaseSteps].contains(field) ? 1 : nil
            return (field, ProductNumberInput.text(product.entity.double(field.rawValue) ?? fallback, locale: locale))
        })
        closeout = product.entity.boolean("isCloseout") ?? false
        shippingFree = product.entity.boolean("shippingFree") ?? false
        deliveryTimeID = product.entity.string("deliveryTimeId") ?? ""
        unitID = product.entity.string("unitId") ?? ""
        packUnit = product.entity.translated("packUnit") ?? ""
        packUnitPlural = product.entity.translated("packUnitPlural") ?? ""
        releaseDate = product.entity.date("releaseDate")
    }
    func validationError(locale: Locale) -> String? {
        for field in ProductInventoryField.allCases {
            let text = numbers[field, default: ""].trimmed
            if text.isEmpty && !field.isRequired { continue }
            let value = field.isInteger ? ProductNumberInput.integer(text).map(Double.init) : ProductNumberInput.decimal(text, locale: locale)
            if value == nil || value! < Double(field.minimum) {
                return String(localized: "Enter a valid value for \(String(localized: field.title)).")
            }
        }
        if let maximum = ProductNumberInput.integer(numbers[.maxPurchase, default: ""]), maximum > 0,
           let minimum = ProductNumberInput.integer(numbers[.minPurchase, default: ""]), maximum < minimum {
            return String(localized: "Maximum purchase must be at least the minimum purchase.")
        }
        return nil
    }
    func payload(comparedTo original: ProductInventoryDraft, locale: Locale) -> [String: JSONValue] {
        var patch: [String: JSONValue] = [:]
        for field in ProductInventoryField.allCases where numbers[field] != original.numbers[field] {
            let text = numbers[field, default: ""]
            patch[field.rawValue] = field.isInteger
                ? ProductNumberInput.integer(text).map(JSONValue.int) ?? .null
                : ProductNumberInput.decimal(text, locale: locale).map(JSONValue.number) ?? .null
        }
        if closeout != original.closeout { patch["isCloseout"] = .bool(closeout) }
        if shippingFree != original.shippingFree { patch["shippingFree"] = .bool(shippingFree) }
        if deliveryTimeID != original.deliveryTimeID { patch["deliveryTimeId"] = nullableField(deliveryTimeID) }
        if unitID != original.unitID { patch["unitId"] = nullableField(unitID) }
        if packUnit != original.packUnit { patch["packUnit"] = nullableField(packUnit) }
        if packUnitPlural != original.packUnitPlural { patch["packUnitPlural"] = nullableField(packUnitPlural) }
        if releaseDate != original.releaseDate {
            patch["releaseDate"] = releaseDate.map { .string($0.ISO8601Format(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: true).timeZone(separator: .colon))) } ?? .null
        }
        return patch
    }
}
