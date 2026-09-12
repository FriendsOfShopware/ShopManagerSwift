import Foundation
import ShopwareAdminAPI

func promotionListCriteria() -> Criteria {
    Criteria().addAssociation("discounts").addAssociation("salesChannels.salesChannel")
}

func promotionDetailCriteria() -> Criteria {
    promotionListCriteria()
        .addAssociation("discounts.discountRules").addAssociation("discounts.promotionDiscountPrices.currency")
        .addAssociation("personaRules").addAssociation("cartRules").addAssociation("orderRules")
        .addAssociation("personaCustomers").addAssociation("setgroups.setGroupRules")
}

func promotionFilters() -> [ListingFilter] {
    [
        .bool(key: "active", label: String(localized: "Enabled"), field: "active", trueLabel: String(localized: "Enabled"), falseLabel: String(localized: "Disabled")),
        .bool(key: "useCodes", label: String(localized: "Requires a code"), field: "useCodes", trueLabel: String(localized: "Yes"), falseLabel: String(localized: "No")),
        .bool(key: "individual", label: String(localized: "Individual codes"), field: "useIndividualCodes", trueLabel: String(localized: "Yes"), falseLabel: String(localized: "No")),
        .options(key: "salesChannel", label: String(localized: "Sales channel"), field: "salesChannels.salesChannelId"),
        .dateRange(key: "validFrom", label: String(localized: "Starts"), field: "validFrom"),
        .dateRange(key: "validUntil", label: String(localized: "Ends"), field: "validUntil"),
    ]
}

func promotionCodeCriteria(_ promotionID: String) -> Criteria {
    Criteria().addFilter(Criteria.equals("promotionId", .string(promotionID))).addSorting("code")
}
