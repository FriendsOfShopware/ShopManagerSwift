import Foundation
import ShopwareAdminAPI

struct ProductGeneralDraft: Equatable {
    var name: String
    var productNumber: String
    var active: Bool
    var ean: String
    var manufacturerNumber: String
    var manufacturerID: String
    var description: JSONValue?
    var metaTitle: String
    var metaDescription: String
    var keywords: String
    var customFields: [String: JSONValue]
    init(_ product: ProductItem? = nil) {
        name = product?.name ?? ""; productNumber = product?.productNumber ?? ""
        active = product?.active ?? false
        ean = product?.entity.string("ean") ?? ""
        manufacturerNumber = product?.entity.string("manufacturerNumber") ?? ""
        manufacturerID = product?.entity.string("manufacturerId") ?? ""
        description = product.map { .string($0.description) }
        metaTitle = product?.entity.translated("metaTitle") ?? ""
        metaDescription = product?.entity.translated("metaDescription") ?? ""
        keywords = product?.entity.translated("keywords") ?? ""
        customFields = product?.customFields ?? [:]
    }
    func validationError(fields: [CustomerCustomFieldSet]) -> String? {
        if name.trimmed.isEmpty { return String(localized: "Enter a product name.") }
        if productNumber.trimmed.isEmpty { return String(localized: "Enter a product number.") }
        return fields.flatMap(\.fields).compactMap { $0.validationError(customFields[$0.name]) }.first
    }
    func payload(comparedTo original: ProductGeneralDraft?) -> [String: JSONValue] {
        let all: [String: JSONValue] = [
            "name": .string(name.trimmed), "productNumber": .string(productNumber.trimmed), "active": .bool(active),
            "ean": nullableField(ean), "manufacturerNumber": nullableField(manufacturerNumber),
            "manufacturerId": nullableField(manufacturerID), "description": description ?? .null,
            "metaTitle": nullableField(metaTitle), "metaDescription": nullableField(metaDescription),
            "keywords": nullableField(keywords), "customFields": .object(customFields),
        ]
        guard let original else { return all }
        let baseline = original.payload(comparedTo: nil)
        return all.filter { baseline[$0.key] != $0.value }
    }
}
