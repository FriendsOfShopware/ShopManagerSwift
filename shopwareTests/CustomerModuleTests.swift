import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct CustomerModuleTests {
    private func customer() -> CustomerDetail {
        parseCustomerDetail(SwEntity(.object([
            "id": "customer-1", "firstName": "Ada", "lastName": "Lovelace", "email": "ada@example.test",
            "groupId": "group-1", "languageId": "language-1", "accountType": "business", "company": "Analytical Ltd",
            "title": "Dr", "active": true, "vatIds": .array(["VAT1", "VAT2"]),
            "customFields": .object(["untouched": .object(["nested": 42])]),
            "tags": .array([.object(["id": "tag-1", "name": "VIP"]), .object(["id": "tag-2", "name": "B2B"])]),
        ])))
    }

    @Test func unchangedDraftDoesNotWriteAndContactEditPreservesUnrelatedFields() {
        var draft = CustomerDraft(customer())
        #expect(!draft.hasChanges)
        #expect(draft.validationError == nil)
        draft.customer.firstName = "Augusta Ada"
        #expect(draft.payload == .object(["id": "customer-1", "firstName": "Augusta Ada"]))
        #expect(draft.removedTagIds.isEmpty)
    }

    @Test func clearingOptionalFieldEmitsNullAndPrivateAccountClearsVAT() {
        var draft = CustomerDraft(customer())
        draft.customer.title = ""
        draft.customer.accountType = "private"
        #expect(draft.payload["title"] == .null)
        #expect(draft.payload["vatIds"] == .array([]))
        #expect(draft.payload["company"] == nil)
    }

    @Test func removedTagsAreExplicitButReorderingIsNotAChange() {
        var draft = CustomerDraft(customer())
        draft.customer.tags.reverse()
        #expect(!draft.hasChanges)
        draft.customer.tags.removeAll { $0.id == "tag-1" }
        #expect(draft.removedTagIds == ["tag-1"])
        #expect(draft.payload["tags"] == .array([.object(["id": "tag-2"])]))
    }

    @Test func editingCustomFieldsDoesNotOverwriteUnknownOrUnchangedValues() {
        var draft = CustomerDraft(customer())
        draft.customer.customFields["delivery"] = "Side door"
        #expect(draft.payload["customFields"] == .object(["delivery": "Side door"]))
        draft.customer.customFields["untouched"] = .null
        #expect(draft.payload["customFields"] == .object(["delivery": "Side door", "untouched": .null]))
    }

    @Test func bulkTagOperationsKeepOtherTagsExceptExplicitReplacement() {
        let record = SwEntity(.object(["id": "c", "tags": .array([.object(["id": "one"]), .object(["id": "two"])])]))
        var draft = CustomerBulkDraft()
        draft.active = false
        #expect(draft.changes(for: record).payload == .object(["id": "c", "active": false]))
        draft.tagMode = "add"
        draft.tagIds = ["three"]
        #expect(draft.changes(for: record).removedTags.isEmpty)
        #expect(draft.changes(for: record).payload["tags"]?.arrayValue?.count == 3)
        draft.tagMode = "remove"
        draft.tagIds = ["one"]
        #expect(draft.changes(for: record).removedTags == ["one"])
        #expect(draft.changes(for: record).payload["tags"] == .array([.object(["id": "two"])]))
        draft.tagMode = "replace"
        draft.tagIds = ["three"]
        #expect(draft.changes(for: record).removedTags == ["one", "two"])
        draft.tagMode = "clear"
        #expect(draft.changes(for: record).payload["tags"] == .array([]))
    }

    @Test func creatingCustomerUsesOneAddressAndTheChosenRegistrationBinding() {
        var draft = CustomerCreateDraft()
        draft.customer = customer()
        draft.customer.salesChannelId = "channel"
        draft.address = EditableAddress(id: "address", firstName: "Other", lastName: "Recipient", street: "Street", city: "City", countryId: "country")
        draft.password = "password"
        let payload = draft.payload(number: "10020", boundToSalesChannel: true)
        #expect(payload["customerNumber"] == "10020")
        #expect(payload["boundSalesChannelId"] == "channel")
        #expect(payload["defaultBillingAddressId"] == "address")
        #expect(payload["defaultShippingAddressId"] == "address")
        #expect(payload["addresses"]?.arrayValue?.count == 1)
        #expect(payload["addresses"]?.arrayValue?.first?["firstName"] == "Other")
        draft.customer.guest = true
        #expect(draft.payload(number: "10020", boundToSalesChannel: false)["password"] == nil)
        #expect(draft.payload(number: "10020", boundToSalesChannel: false)["boundSalesChannelId"] == .null)
    }

    @Test func cartErrorsAndTotalsUseServerCalculatedValues() {
        let cart = CustomerOrderCart(json: .object([
            "price": .object(["totalPrice": 42]),
            "deliveries": .array([.object(["shippingCosts": .object(["totalPrice": 5])])]),
            "errors": .object(["stock": .object(["blockOrder": true, "message": "Not available"])]),
        ]))
        #expect(cart.blocksCheckout)
        #expect(cart.messages.first?.string("message") == "Not available")
        #expect(cart.total == 42)
        #expect(cart.shipping == 5)
        #expect(!CustomerOrderCart(json: .object(["errors": .array([])])).blocksCheckout)
    }

    @Test func editingAnAddressOnlyWritesChangedFieldsAndCustomValues() {
        let original = EditableAddress(id: "address", firstName: "Ada", lastName: "Lovelace", street: "Old street",
                                       customFields: ["plugin": .object(["keep": true]), "note": "Old note"])
        var edited = original
        edited.street = "New street"
        edited.customFields["note"] = .null
        let payload = customerAddressSavePayload(customerId: "customer", address: edited, defaultBilling: false,
                                                defaultShipping: false, original: original)
        #expect(payload["addresses"] == .array([.object([
            "id": "address", "street": "New street", "customFields": .object(["note": .null]),
        ])]))
    }

    @Test func tagLinkChangesRequireTheirSpecificPrivileges() {
        var draft = CustomerDraft(customer())
        let editor = AdminPermissions(privileges: ["customer:update", "customer_tag:create"])
        #expect(draft.tagPermissionError(editor) == nil)
        draft.customer.tags.removeFirst()
        #expect(draft.tagPermissionError(editor) != nil)
        #expect(draft.tagPermissionError(AdminPermissions(isAdmin: true)) == nil)
    }

    @Test func storefrontLoginKeepsTokenOutOfURLAndEscapesFormSeparators() throws {
        let request = customerImitationRequest(domain: try #require(URL(string: "https://shop.test/en")), token: "a+b&c=d?e#f",
                                              customerId: "customer", userId: "user")
        #expect(request.url?.absoluteString == "https://shop.test/en/account/login/imitate-customer")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "token=a%2Bb%26c%3Dd%3Fe%23f&customerId=customer&userId=user")
    }

    @Test func validatesPasswordsBusinessCompanyAndRealCalendarDates() {
        var draft = CustomerDraft(customer())
        draft.password = "new-password"
        #expect(draft.validationError != nil)
        draft.passwordConfirmation = draft.password
        #expect(draft.validationError == nil)
        draft.customer.company = "  "
        #expect(draft.validationError != nil)
        #expect(CustomerDraft.validBirthday("2024-02-29"))
        #expect(!CustomerDraft.validBirthday("2023-02-29"))
        #expect(!CustomerDraft.validBirthday("2024-13-01"))
        #expect(!CustomerDraft.validBirthday("2024-2-1"))
    }

    @Test func addressPayloadPreservesIndependentRecipientAndAllAddressFields() {
        let address = parseEditableAddress(SwEntity(.object([
            "id": "address-1", "firstName": "Charles", "lastName": "Babbage", "street": "1 Example Street",
            "zipcode": "12345", "city": "Example", "countryId": "country-1", "countryStateId": "state-1",
            "additionalAddressLine1": "Floor 2", "additionalAddressLine2": "Room 3", "department": "Research",
            "customFields": .object(["delivery-note": "Doorbell"]),
        ])))
        let payload = customerAddressSavePayload(customerId: "customer-1", address: address, defaultBilling: true, defaultShipping: false)
        #expect(payload["defaultBillingAddressId"] == "address-1")
        #expect(payload["defaultShippingAddressId"] == nil)
        let saved = payload["addresses"]?.arrayValue?.first
        #expect(saved?["firstName"] == "Charles")
        #expect(saved?["additionalAddressLine2"] == "Room 3")
        #expect(saved?["countryStateId"] == "state-1")
        #expect(saved?["customFields"] == .object(["delivery-note": "Doorbell"]))
    }

    @Test func countryRequirementsControlAddressValidation() {
        var address = EditableAddress(id: "a", firstName: "Ada", lastName: "Lovelace", street: "Street", city: "City", countryId: "c")
        let country = CountryOption(id: "c", name: "Country", postalCodeRequired: true, forceStateInRegistration: true)
        #expect(address.validationError(country: country, business: false) != nil)
        address.zipcode = "12345"
        #expect(address.validationError(country: country, business: false) != nil)
        address.countryStateId = "state"
        #expect(address.validationError(country: country, business: false) == nil)
        #expect(address.validationError(country: country, business: true) != nil)
    }

    @Test func managementListingLoadsRequiredAssociationsAndSortsNewestFirst() {
        let criteria = customerManagementCriteria().toJSON()
        #expect(criteria["sort"]?.arrayValue?.first == .object(["field": "createdAt", "order": "DESC"]))
        #expect(criteria["associations"]?["requestedGroup"] != nil)
        #expect(criteria["associations"]?["defaultBillingAddress"] != nil)
        let row = parseCustomerRow(SwEntity(.object([
            "firstName": "Ada", "lastName": "Lovelace", "group": .object(["translated": .object(["name": "Wholesale"]) ]),
            "defaultBillingAddress": .object(["city": "London"]),
        ])))
        #expect(row.name == "Ada Lovelace")
        #expect(row.group == "Wholesale")
        #expect(row.city == "London")
    }

    @Test func serverSortingResetsPageAndKeepsSearchAndFilters() async {
        var received: [JSONValue] = []
        let state = ListingState<CustomerRow>(filters: [.bool(key: "active", label: "Status", field: "active", trueLabel: "Active", falseLabel: "Disabled")], source: { criteria in
            received.append(criteria.toJSON())
            return SearchResult(total: 100, data: [], aggregations: .object([:]))
        }, baseCriteria: customerManagementCriteria, mapper: parseCustomerRow)
        state.setTerm("Ada")
        state.setFilterValue("active", .options(["true"]))
        await state.fetchTask?.value
        state.loadMore()
        await state.fetchTask?.value
        state.setSorting([ListingSort(field: "customerNumber", ascending: true, natural: true)])
        await state.fetchTask?.value
        #expect(received.last?["page"] == 1)
        #expect(received.last?["term"] == "Ada")
        #expect(received.last?["filter"]?.arrayValue?.first == Criteria.equals("active", true))
        #expect(received.last?["sort"]?.arrayValue == [.object(["field": "customerNumber", "order": "ASC", "naturalSorting": true])])
    }
}
