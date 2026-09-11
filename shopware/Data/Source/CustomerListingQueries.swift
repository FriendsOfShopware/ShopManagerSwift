import Foundation
import ShopwareAdminAPI

func customerManagementCriteria() -> Criteria {
    Criteria().addSorting("createdAt", "DESC").addSorting("id")
        .addAssociation("defaultBillingAddress").addAssociation("group")
        .addAssociation("requestedGroup").addAssociation("boundSalesChannel")
        .addIncludes("customer", ["id", "firstName", "lastName", "email", "customerNumber", "active", "guest",
                                  "company", "createdAt", "affiliateCode", "campaignCode", "orderCount", "orderTotalAmount",
                                  "defaultBillingAddress", "group", "requestedGroup", "boundSalesChannel"])
        .addIncludes("customer_address", ["street", "zipcode", "city"])
        .addIncludes("customer_group", ["name", "translated"])
        .addIncludes("sales_channel", ["name", "translated"])
}

func parseCustomerRow(_ c: SwEntity) -> CustomerRow {
    let name = [c.string("firstName"), c.string("lastName")].compactMap { $0 }.joined(separator: " ")
    let address = c.entity("defaultBillingAddress")
    return CustomerRow(
        id: c.id ?? "", name: name.isEmpty ? "—" : name,
        orderCount: c.int("orderCount") ?? 0, totalSpend: c.double("orderTotalAmount") ?? 0,
        email: c.string("email") ?? "", customerNumber: c.string("customerNumber") ?? "",
        active: c.boolean("active") ?? false, guest: c.boolean("guest") ?? false,
        company: c.string("company") ?? "", group: c.entity("group")?.translated("name") ?? "—",
        street: address?.string("street") ?? "", zipcode: address?.string("zipcode") ?? "", city: address?.string("city") ?? "",
        createdAt: c.date("createdAt") ?? .distantPast,
        boundSalesChannel: c.entity("boundSalesChannel")?.translated("name") ?? String(localized: "All sales channels"),
        affiliateCode: c.string("affiliateCode") ?? "", campaignCode: c.string("campaignCode") ?? "",
        requestedGroup: c.entity("requestedGroup")?.translated("name")
    )
}
