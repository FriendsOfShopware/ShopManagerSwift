import Foundation
import ShopwareAdminAPI

extension ShopApi {
    /// Loads a single customer with billing/shipping addresses and group.
    func fetchCustomerDetail(_ customerId: String) async throws -> CustomerDetail? {
        guard let c = try await repository("customer").get(
            customerId,
            criteria: Criteria()
                .addAssociation("defaultBillingAddress.country")
                .addAssociation("defaultBillingAddress.countryState")
                .addAssociation("defaultShippingAddress.country")
                .addAssociation("defaultShippingAddress.countryState")
                .addAssociation("group").addAssociation("requestedGroup")
                .addAssociation("language").addAssociation("salesChannel")
                .addAssociation("boundSalesChannel").addAssociation("tags")
        ) else { return nil }
        return parseCustomerDetail(c)
    }
}

func parseCustomerDetail(_ c: SwEntity) -> CustomerDetail {
        let billing = c.entity("defaultBillingAddress")
        let shipping = c.entity("defaultShippingAddress")
        let billingId = c.string("defaultBillingAddressId")
        let shippingId = c.string("defaultShippingAddressId")

        let billingFormatted = billing.map { parseEditableAddress($0).formatted }
        let shippingFormatted = shipping.map { parseEditableAddress($0).formatted }

        return CustomerDetail(
            id: c.id ?? "",
            name: [c.string("firstName"), c.string("lastName")]
                .compactMap { $0 }
                .joined(separator: " ")
                .ifBlank("—"),
            email: c.string("email") ?? "",
            customerNumber: c.string("customerNumber") ?? "",
            group: c.entity("group")?.translated("name"),
            active: c.boolean("active") ?? false,
            guest: c.boolean("guest") ?? false,
            orderCount: c.int("orderCount") ?? 0,
            totalSpend: c.double("orderTotalAmount") ?? 0.0,
            lastOrderMs: c.date("lastOrderDate")?.epochMs,
            customerSince: c.date("createdAt").map {
                $0.formatted(date: .abbreviated, time: .omitted)
            },
            billingAddress: billingFormatted,
            shippingAddress: shippingFormatted,
            phone: billing?.string("phoneNumber") ?? shipping?.string("phoneNumber"),
            firstName: c.string("firstName") ?? "",
            lastName: c.string("lastName") ?? "",
            title: c.string("title"),
            company: c.string("company"),
            salutationId: c.string("salutationId"),
            billing: billing.map(parseEditableAddress),
            shipping: shipping.map(parseEditableAddress),
            sharedAddress: billingId != nil && billingId == shippingId,
            accountType: c.string("accountType") ?? "private",
            vatIds: c.json["vatIds"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            groupId: c.string("groupId") ?? "",
            languageId: c.string("languageId") ?? "",
            language: c.entity("language")?.translated("name") ?? "",
            salesChannelId: c.string("salesChannelId") ?? "",
            salesChannel: c.entity("salesChannel")?.translated("name") ?? "",
            boundSalesChannelId: c.string("boundSalesChannelId"),
            boundSalesChannel: c.entity("boundSalesChannel")?.translated("name"),
            lastLogin: c.date("lastLogin"), birthday: c.string("birthday").map { String($0.prefix(10)) },
            affiliateCode: c.string("affiliateCode"), campaignCode: c.string("campaignCode"),
            doubleOptInRegistration: c.boolean("doubleOptInRegistration") ?? false,
            doubleOptInConfirmDate: c.date("doubleOptInConfirmDate"),
            requestedGroupId: c.string("requestedGroupId"),
            requestedGroup: c.entity("requestedGroup")?.translated("name"),
            tags: c.entities("tags").compactMap { tag in tag.id.map { CustomerOption(id: $0, name: tag.string("name") ?? "") } },
            customFields: c.json["customFields"]?.objectValue ?? [:],
            createdByAdmin: c.string("createdById") != nil,
            defaultBillingAddressId: billingId, defaultShippingAddressId: shippingId
        )
}

/// Maps a customer_address entity into the editable form model.
func parseEditableAddress(_ a: SwEntity) -> EditableAddress {
    EditableAddress(
        id: a.id ?? "",
        firstName: a.string("firstName") ?? "",
        lastName: a.string("lastName") ?? "",
        street: a.string("street") ?? "",
        additionalLine: a.string("additionalAddressLine1"),
        zipcode: a.string("zipcode") ?? "",
        city: a.string("city") ?? "",
        company: a.string("company"),
        phoneNumber: a.string("phoneNumber"),
        countryId: a.string("countryId"),
        countryName: a.entity("country")?.translated("name"),
        salutationId: a.string("salutationId"), title: a.string("title"), department: a.string("department"),
        additionalLine2: a.string("additionalAddressLine2"), countryStateId: a.string("countryStateId"),
        countryStateName: a.entity("countryState")?.translated("name"),
        customFields: a.json["customFields"]?.objectValue ?? [:]
    )
}

extension ShopApi {
    /// Patch only customer-level contact fields. Empty optional strings are sent as null.
    func saveCustomerContact(
        customerId: String,
        firstName: String,
        lastName: String,
        email: String,
        salutationId: String?,
        title: String?,
        company: String?
    ) async throws {
        var fields: [String: JSONValue] = [
            "firstName": .string(firstName),
            "lastName": .string(lastName),
            "email": .string(email)
        ]
        if let salutationId {
            fields["salutationId"] = .string(salutationId)
        }
        fields["title"] = nullableField(title)
        fields["company"] = nullableField(company)
        try await repository("customer").patch(customerId, .object(fields))
    }

    /// Patch one customer_address record.
    func saveCustomerAddress(_ address: EditableAddress) async throws {
        try await repository("customer-address").patch(address.id, address.payload)
    }

    /// Loads all salutations ordered by key for selection.
    func fetchSalutations() async throws -> [SalutationOption] {
        try await repository("salutation").search(
            Criteria()
                .addSorting("salutationKey")
                .addIncludes("salutation", ["id", "displayName", "translated", "salutationKey"])
        ).data.compactMap { s in
            s.id.map { SalutationOption(id: $0, label: s.translated("displayName") ?? s.string("salutationKey") ?? "—") }
        }
    }

    /// Loads active countries ordered by name for selection.
    func fetchCountries() async throws -> [CountryOption] {
        try await repository("country").search(
            Criteria()
                .setLimit(500)
                .addFilter(Criteria.equals("active", .bool(true)))
                .addSorting("name")
                .addIncludes("country", ["id", "name", "translated", "postalCodeRequired", "forceStateInRegistration"])
        ).data.compactMap { c in
            c.id.map { CountryOption(id: $0, name: c.translated("name") ?? "—",
                                     postalCodeRequired: c.boolean("postalCodeRequired") ?? false,
                                     forceStateInRegistration: c.boolean("forceStateInRegistration") ?? false) }
        }
    }

    func customerOptions(_ entity: String, criteria: Criteria = Criteria(), label: String = "name") async throws -> [CustomerOption] {
        var options: [CustomerOption] = []
        var page = 1
        while true {
            let result = try await repository(entity).search(criteria.setPage(page).setLimit(100).setTotalCountMode(.exact))
            options += result.data.compactMap { item in
                item.id.map { CustomerOption(id: $0, name: item.translated(label) ?? "—") }
            }
            if result.data.isEmpty || page * 100 >= result.total { return options }
            page += 1
        }
    }

    func customerAddressListing(customerId: String) -> ListingState<EditableAddress> {
        ListingState(
            source: { try await self.repository("customer-address").search($0) },
            baseCriteria: {
                Criteria().addFilter(Criteria.equals("customerId", .string(customerId)))
                    .addAssociation("country").addAssociation("countryState")
                    .addSorting("lastName").addSorting("firstName").addSorting("id")
            }, mapper: parseEditableAddress
        )
    }
}

private extension String {
    /// Returns `fallback` when the string is empty, otherwise self.
    func ifBlank(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
