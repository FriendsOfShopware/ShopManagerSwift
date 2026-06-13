import Foundation
import ShopwareAdminAPI

extension ShopApi {
    /// Loads a single customer with billing/shipping addresses and group.
    func fetchCustomerDetail(_ customerId: String) async throws -> CustomerDetail? {
        guard let c = try await repository("customer").get(
            customerId,
            criteria: Criteria()
                .addAssociation("defaultBillingAddress.country")
                .addAssociation("defaultShippingAddress.country")
                .addAssociation("group")
        ) else { return nil }

        let billing = c.entity("defaultBillingAddress")
        let shipping = c.entity("defaultShippingAddress")
        let billingId = c.string("defaultBillingAddressId")
        let shippingId = c.string("defaultShippingAddressId")

        let billingFormatted = billing.flatMap(formatAddress)
        let shippingFormatted = shipping.flatMap(formatAddress)

        return CustomerDetail(
            id: customerId,
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
                $0.formatted(.dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
            },
            billingAddress: billingFormatted,
            shippingAddress: shippingFormatted == billingFormatted ? nil : shippingFormatted,
            phone: billing?.string("phoneNumber") ?? shipping?.string("phoneNumber"),
            firstName: c.string("firstName") ?? "",
            lastName: c.string("lastName") ?? "",
            title: c.string("title"),
            company: c.string("company"),
            salutationId: c.string("salutationId"),
            billing: billing.map(parseEditableAddress),
            shipping: shipping.map(parseEditableAddress),
            sharedAddress: billingId != nil && billingId == shippingId
        )
    }
}

/// Maps a customer_address entity into the editable form model.
private func parseEditableAddress(_ a: SwEntity) -> EditableAddress {
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
        countryName: a.entity("country")?.translated("name")
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
        var fields: [String: JSONValue] = [
            "firstName": .string(address.firstName),
            "lastName": .string(address.lastName),
            "street": .string(address.street),
            "zipcode": .string(address.zipcode),
            "city": .string(address.city)
        ]
        if let countryId = address.countryId {
            fields["countryId"] = .string(countryId)
        }
        fields["additionalAddressLine1"] = nullableField(address.additionalLine)
        fields["company"] = nullableField(address.company)
        fields["phoneNumber"] = nullableField(address.phoneNumber)
        try await repository("customer-address").patch(address.id, .object(fields))
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
                .addIncludes("country", ["id", "name", "translated"])
        ).data.compactMap { c in
            c.id.map { CountryOption(id: $0, name: c.translated("name") ?? "—") }
        }
    }
}

private extension String {
    /// Returns `fallback` when the string is empty, otherwise self.
    func ifBlank(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
