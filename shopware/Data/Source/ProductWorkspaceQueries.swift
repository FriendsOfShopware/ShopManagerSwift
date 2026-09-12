import Foundation
import ShopwareAdminAPI

func productWorkspaceCriteria(parentID: String? = nil) -> Criteria {
    Criteria().addFilter(Criteria.equals("parentId", parentID.map(JSONValue.string)))
        .addAssociation("cover.media").addAssociation("manufacturer").addAssociation("tax")
        .addAssociation("options.group").addSorting("name").addSorting("id")
}

func productWorkspaceDetailCriteria() -> Criteria {
    Criteria().addAssociation("manufacturer").addAssociation("tax")
        .addAssociation("cover.media").addAssociation("media.media")
        .addAssociation("categories").addAssociation("properties.group").addAssociation("tags")
        .addAssociation("visibilities.salesChannel").addAssociation("options.group")
        .addAssociation("prices.rule").addAssociation("deliveryTime").addAssociation("unit")
}

func productWorkspaceFilters() -> [ListingFilter] {
    [
        .bool(key: "active", label: String(localized: "Status"), field: "active", trueLabel: String(localized: "Active"), falseLabel: String(localized: "Inactive")),
        .numberRange(key: "stock", label: String(localized: "Stock"), field: "stock"),
        .numberRange(key: "price", label: String(localized: "Price"), field: "price"),
        .options(key: "manufacturer", label: String(localized: "Manufacturer"), field: "manufacturerId"),
        .options(key: "salesChannel", label: String(localized: "Sales channel"), field: "visibilities.salesChannelId"),
        .options(key: "categories", label: String(localized: "Categories"), field: "categories.id"),
        .options(key: "tags", label: String(localized: "Tags"), field: "tags.id"),
        .existence(key: "images", label: String(localized: "Images"), field: "media.id", hasLabel: String(localized: "Has images"), hasNotLabel: String(localized: "No images")),
        .text(key: "productNumber", label: String(localized: "Product number"), field: "productNumber", mode: .contains),
        .dateRange(key: "releaseDate", label: String(localized: "Release date"), field: "releaseDate"),
    ]
}
