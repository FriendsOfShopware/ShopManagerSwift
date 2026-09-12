import Foundation
import ShopwareAdminAPI

struct PromotionItem: Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var active: Bool
    var priority: Int
    var validFrom: Date?
    var validUntil: Date?
    var createdAt: Date?
    var orderCount: Int
    var maxRedemptionsGlobal: Int?
    var maxRedemptionsPerCustomer: Int?
    var codeMode: PromotionCodeMode
    var code: String
    var codePattern: String
    var preventCombination: Bool
    var exclusionIDs: Set<String>
    var useSetGroups: Bool
    var customerRestriction: Bool
    var salesChannels: [PromotionReference]
    var personaRules: [PromotionReference]
    var cartRules: [PromotionReference]
    var orderRules: [PromotionReference]
    var customers: [PromotionReference]
    var setGroups: [PromotionSetGroup]
    var discounts: [PromotionDiscount]
    var customFields: [String: JSONValue]

    init(_ entity: SwEntity) {
        id = entity.id ?? ""
        name = entity.translated("name") ?? String(localized: "Unnamed promotion")
        active = entity.boolean("active") ?? false
        priority = entity.int("priority") ?? 1
        validFrom = entity.date("validFrom"); validUntil = entity.date("validUntil"); createdAt = entity.date("createdAt")
        orderCount = entity.int("orderCount") ?? 0
        maxRedemptionsGlobal = entity.int("maxRedemptionsGlobal")
        maxRedemptionsPerCustomer = entity.int("maxRedemptionsPerCustomer")
        codeMode = entity.boolean("useCodes") != true ? .automatic : entity.boolean("useIndividualCodes") == true ? .individual : .fixed
        code = entity.string("code") ?? ""
        codePattern = entity.string("individualCodePattern") ?? ""
        preventCombination = entity.boolean("preventCombination") ?? false
        exclusionIDs = Set(entity.json["exclusionIds"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        useSetGroups = entity.boolean("useSetGroups") ?? false
        customerRestriction = entity.boolean("customerRestriction") ?? false
        salesChannels = entity.entities("salesChannels").compactMap { link in
            guard let id = link.string("salesChannelId") ?? link.entity("salesChannel")?.id else { return nil }
            return PromotionReference(id: id, name: link.entity("salesChannel")?.translated("name") ?? id, mappingID: link.id)
        }
        personaRules = entity.entities("personaRules").map { PromotionReference($0) }
        cartRules = entity.entities("cartRules").map { PromotionReference($0) }
        orderRules = entity.entities("orderRules").map { PromotionReference($0) }
        customers = entity.entities("personaCustomers").map { PromotionReference($0) }
        setGroups = entity.entities("setgroups").map { PromotionSetGroup($0) }
        discounts = entity.entities("discounts").map { PromotionDiscount($0) }
        customFields = entity.json["customFields"]?.objectValue ?? entity.json["translated"]?["customFields"]?.objectValue ?? [:]
    }

    func state(at now: Date = Date()) -> PromotionState {
        if !active { return .inactive }
        if let validUntil, validUntil <= now { return .expired }
        if let validFrom, validFrom > now { return .scheduled }
        return .active
    }
    var fromOrder: Double { validFrom?.timeIntervalSince1970 ?? -.infinity }
    var untilOrder: Double { validUntil?.timeIntervalSince1970 ?? .infinity }
    var createdOrder: Double { createdAt?.timeIntervalSince1970 ?? 0 }
}
