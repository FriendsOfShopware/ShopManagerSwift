import Foundation
import ShopwareAdminAPI

/// Patches only general settings; discount definitions and all associations remain untouched.
struct PromotionDraft: Equatable {
    var name = ""
    var active = false
    var priority = "1"
    var hasStart = false
    var hasEnd = false
    var starts = Date()
    var ends = Date().addingTimeInterval(86400 * 7)
    var globalLimit = ""
    var customerLimit = ""
    var codeMode = PromotionCodeMode.automatic
    var code = ""
    var codePattern = "%s%d%s%d%s%d%s%d"
    var customFields: [String: JSONValue] = [:]

    init(_ promotion: PromotionItem? = nil) {
        guard let promotion else { return }
        name = promotion.name; active = promotion.active; priority = String(promotion.priority)
        hasStart = promotion.validFrom != nil; hasEnd = promotion.validUntil != nil
        starts = promotion.validFrom ?? starts; ends = promotion.validUntil ?? ends
        globalLimit = promotion.maxRedemptionsGlobal.map(String.init) ?? ""
        customerLimit = promotion.maxRedemptionsPerCustomer.map(String.init) ?? ""
        codeMode = promotion.codeMode; code = promotion.code; codePattern = promotion.codePattern
        customFields = promotion.customFields
    }
    func validationError(sets: [CustomerCustomFieldSet]) -> String? {
        if name.trimmed.isEmpty { return String(localized: "Enter a promotion name.") }
        if Int(priority).map({ $0 >= 0 }) != true { return String(localized: "Priority must be a whole number of zero or greater.") }
        if hasStart && hasEnd && ends <= starts { return String(localized: "The end must be after the start.") }
        for limit in [globalLimit, customerLimit] where !limit.trimmed.isEmpty {
            if Int(limit).map({ $0 > 0 }) != true { return String(localized: "Redemption limits must be positive whole numbers, or empty for no limit.") }
        }
        if codeMode == .fixed && code.trimmed.isEmpty { return String(localized: "Enter a promotion code.") }
        if codeMode == .individual && !codePattern.contains("%s") && !codePattern.contains("%d") {
            return String(localized: "Include %s for letters or %d for digits in the code pattern.")
        }
        return sets.flatMap(\.fields).compactMap { $0.validationError(customFields[$0.name]) }.first
    }
    var payload: [String: JSONValue] {
        ["name": .string(name.trimmed), "active": .bool(active), "priority": .int(Int(priority) ?? 1),
         "validFrom": hasStart ? .string(starts.ISO8601Format(.init(includingFractionalSeconds: true))) : .null,
         "validUntil": hasEnd ? .string(ends.ISO8601Format(.init(includingFractionalSeconds: true))) : .null,
         "maxRedemptionsGlobal": Int(globalLimit).map(JSONValue.int) ?? .null,
         "maxRedemptionsPerCustomer": Int(customerLimit).map(JSONValue.int) ?? .null,
         "useCodes": .bool(codeMode != .automatic), "useIndividualCodes": .bool(codeMode == .individual),
         "code": codeMode == .fixed ? .string(code.trimmed) : .null,
         "individualCodePattern": .string(codePattern), "customFields": .object(customFields)]
    }
}
