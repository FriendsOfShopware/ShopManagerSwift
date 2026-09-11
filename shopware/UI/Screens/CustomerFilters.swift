import Foundation
import ShopwareAdminAPI

func customerFilters() -> [ListingFilter] {
    [
        .text(key: "customerNumber", label: String(localized: "Customer number"), field: "customerNumber", mode: .equals),
        customerOptionFilter("group", "Customer group", "groupId", "customer-group"),
        .bool(key: "active", label: String(localized: "Account status"), field: "active", trueLabel: String(localized: "Active"), falseLabel: String(localized: "Disabled")),
        .bool(key: "guest", label: String(localized: "Registration"), field: "guest", trueLabel: String(localized: "Guest"), falseLabel: String(localized: "Registered")),
        .options(key: "accountType", label: String(localized: "Account type"), field: "accountType", staticOptions: [
            FilterOption(id: "private", label: String(localized: "Private")), FilterOption(id: "business", label: String(localized: "Business")),
        ]),
        .existence(key: "requestedGroup", label: String(localized: "Group request"), field: "requestedGroupId", hasLabel: String(localized: "Pending request"), hasNotLabel: String(localized: "No pending request")),
        customerOptionFilter("salutation", "Salutation", "salutationId", "salutation", label: "displayName"),
        customerOptionFilter("billingCountry", "Billing country", "defaultBillingAddress.countryId", "country"),
        customerOptionFilter("shippingCountry", "Shipping country", "defaultShippingAddress.countryId", "country"),
        customerOptionFilter("tags", "Tags", "tags.id", "tag"),
        salesChannelFilter(label: String(localized: "Registration sales channel")),
        customerOptionFilter("boundSalesChannel", "Bound sales channel", "boundSalesChannelId", "sales-channel"),
        .dateRange(key: "createdAt", label: String(localized: "Registration date"), field: "createdAt"),
        .numberRange(key: "orderCount", label: String(localized: "Order count"), field: "orderCount"),
        .text(key: "affiliateCode", label: String(localized: "Affiliate code"), field: "affiliateCode"),
        .text(key: "campaignCode", label: String(localized: "Campaign code"), field: "campaignCode"),
    ]
}

private func customerOptionFilter(_ key: String, _ title: LocalizedStringResource, _ field: String, _ entity: String, label: String = "name") -> ListingFilter {
    .options(key: key, label: String(localized: title), field: field, loadOptions: { api in
        try await api.customerOptions(entity, criteria: Criteria().addSorting(label), label: label)
            .map { FilterOption(id: $0.id, label: $0.name) }
    })
}
