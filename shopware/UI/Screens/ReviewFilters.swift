import Foundation
import ShopwareAdminAPI

func reviewFilters() -> [ListingFilter] {
    [
        .bool(key: "status", label: String(localized: "Approval"), field: "status", trueLabel: String(localized: "Approved"), falseLabel: String(localized: "Pending")),
        .options(key: "salesChannel", label: String(localized: "Sales channel"), field: "salesChannelId"),
        .options(key: "language", label: String(localized: "Language"), field: "languageId"),
        .options(key: "customer", label: String(localized: "Customer"), field: "customerId"),
        .options(key: "product", label: String(localized: "Product"), field: "productId"),
        .numberRange(key: "points", label: String(localized: "Rating"), field: "points"),
    ]
}
