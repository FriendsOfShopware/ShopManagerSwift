import ShopwareDomain
import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct ProductModuleTests {
    private func api(_ transport: ProductUITestTransport) -> ShopApi {
        ShopApi(baseURL: "https://product-ui.test", auth: .refreshToken(token: "fixture"), transport: transport)
    }
    private func product(_ fields: [String: JSONValue] = [:]) -> ProductItem {
        var raw: [String: JSONValue] = [
            "id": "product", "name": "Linen shirt", "productNumber": "SW-100", "active": true, "stock": .int(10),
            "price": .array([
                .object(["currencyId": "other-currency", "gross": .number(75), "net": .number(60), "linked": false]),
                .object(["currencyId": .string(ShopwareDefaults.currencyID), "gross": .number(49.123456789), "net": .number(40), "linked": false,
                         "listPrice": .object(["gross": .number(59), "net": .number(50), "linked": false]),
                         "regulationPrice": .object(["gross": .number(45), "net": .number(38), "linked": false])]),
            ]),
            "description": "<p>A <strong>linen</strong> shirt.</p>",
            "customFields": .object(["external_id": "keep-me"]),
        ]
        raw.merge(fields) { _, new in new }
        return ProductItem(SwEntity(.object(raw)), shopURL: "https://shop.test")
    }
    @Test func defaultCurrencyIsIdentifiedByIDInsteadOfArrayPosition() {
        let item = product()
        #expect(item.grossPrice == 49.123456789)
        let missing = product(["price": .array([.object(["currencyId": "other", "gross": .number(25)])])])
        #expect(missing.grossPrice == nil)
    }
    @Test func priceEditsPreserveOtherCurrenciesAndReferencePrices() throws {
        let item = product(), locale = Locale(identifier: "de_DE")
        var draft = ProductPriceDraft(price: item.defaultPrice, locale: locale)
        #expect(draft.gross == "49,123456789")
        #expect(draft.prices(replacing: item.prices, locale: locale) == item.prices)
        draft.gross = "51,25"; draft.net = "43,06722689"
        let updated = try #require(draft.prices(replacing: item.prices, locale: locale))
        #expect(updated[0] == item.prices[0])
        #expect(updated[1]["listPrice"] == item.prices[1]["listPrice"])
        #expect(updated[1]["regulationPrice"] == item.prices[1]["regulationPrice"])
        #expect(updated[1]["gross"]?.doubleValue == 51.25)
    }
    @Test func linkedPricesValidateLocaleAndRejectInvalidInput() {
        let locale = Locale(identifier: "de_DE")
        var draft = ProductPriceDraft(price: nil, locale: locale)
        draft.updateGross("119", taxRate: 19, locale: locale)
        #expect(ProductNumberInput.decimal(draft.net, locale: locale) == 100)
        draft.updateNet("50", taxRate: 19, locale: locale)
        #expect(ProductNumberInput.decimal(draft.gross, locale: locale) == 59.5)
        for invalid in ["", "-1", "NaN", "Infinity", "2.5", "1,2,3", "1 000"] {
            draft.gross = invalid
            #expect(draft.validationError(locale: locale) != nil)
            #expect(draft.prices(replacing: [], locale: locale) == nil)
        }
        draft.gross = "0"; draft.net = "0"
        #expect(draft.validationError(locale: locale) == nil)
    }
    @Test func unrelatedGeneralEditsPreserveInheritedValuesAndHTML() {
        let item = product(["parentId": "parent", "ean": "parent-ean", "manufacturerId": "brand"])
        let original = ProductGeneralDraft(item)
        var draft = original; draft.name = "Updated variant"
        #expect(draft.payload(comparedTo: original) == ["name": "Updated variant"])
        #expect(original.payload(comparedTo: original).isEmpty)
        draft.ean = ""
        #expect(draft.payload(comparedTo: original)["ean"] == .null)
        #expect(draft.payload(comparedTo: original)["description"] == nil)
        #expect(draft.payload(comparedTo: original)["customFields"] == nil)
    }
    @Test func generalValidationRequiresNameAndNumberAndValidCustomFields() {
        var draft = ProductGeneralDraft()
        #expect(draft.validationError(fields: []) != nil)
        draft.name = "Product"
        #expect(draft.validationError(fields: []) != nil)
        draft.productNumber = "SW-101"
        #expect(draft.validationError(fields: []) == nil)
        #expect(draft.active == false)
    }
    @Test func inventoryPreservesNegativeStockAndRejectsInvalidPurchaseLimits() {
        let locale = Locale(identifier: "en_US")
        let item = product(["stock": .int(-2)])
        let original = ProductInventoryDraft(item, locale: locale)
        #expect(original.validationError(locale: locale) == nil)
        var draft = original; draft.numbers[.minPurchase] = "0"
        #expect(draft.validationError(locale: locale) != nil)
        draft.numbers[.minPurchase] = "5"; draft.numbers[.maxPurchase] = "3"
        #expect(draft.validationError(locale: locale) != nil)
        draft.numbers[.maxPurchase] = "0"
        #expect(draft.validationError(locale: locale) == nil)
        draft.numbers[.stock] = "999999999999999999"
        #expect(draft.validationError(locale: locale) != nil)
    }
    @Test func inventoryWritesOnlyChangesAndUsesCompleteDateTimes() throws {
        let locale = Locale(identifier: "de_DE")
        let original = ProductInventoryDraft(product(["weight": .number(0.123456789), "releaseDate": "2026-09-01T10:00:00.123Z"]), locale: locale)
        var draft = original; draft.numbers[.stock] = "20"
        #expect(draft.payload(comparedTo: original, locale: locale) == ["stock": .int(20)])
        let date = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-10-01T11:30:00.123Z")
        draft.releaseDate = date
        #expect(draft.payload(comparedTo: original, locale: locale)["releaseDate"] == "2026-10-01T11:30:00.123Z")
        draft.releaseDate = nil
        #expect(draft.payload(comparedTo: original, locale: locale)["releaseDate"] == .null)
    }
    @Test func assignmentChangesIncludeVisibilityAndCompositeVersionKeys() throws {
        let original = product([
            "categories": .array([.object(["id": "category-old"])]),
            "visibilities": .array([.object(["id": "visibility-old", "salesChannelId": "channel-old", "visibility": .int(10)])]),
        ])
        var draft = ProductOrganizationDraft(original)
        draft.categories = ["category-new"]; draft.visibilities = ["channel-new": 20]
        let operations = draft.operations(for: original)
        #expect(operations == draft.operations(for: original))
        let removed = try #require(operations["remove-product_category"]?["payload"]?.arrayValue?.first)
        #expect(removed["productId"] == "product")
        #expect(removed["productVersionId"]?.stringValue == ShopwareDefaults.liveVersionID)
        #expect(removed["categoryVersionId"]?.stringValue == ShopwareDefaults.liveVersionID)
        let mapping = try #require(operations["save-product"]?["payload"]?.arrayValue?.first?["visibilities"]?.arrayValue?.first)
        #expect(mapping["visibility"] == .int(20))
        #expect(mapping["salesChannelId"] == "channel-new")
        #expect(mapping["id"]?.stringValue?.count == 32)
    }
    @Test func unchangedAssignmentsAreNotRewritten() {
        let original = product(["visibilities": .array([.object(["id": "visibility", "salesChannelId": "channel", "visibility": .int(10)])])])
        var draft = ProductOrganizationDraft(original); draft.tags = ["tag"]
        let patch = draft.operations(for: original)["save-product"]?["payload"]?.arrayValue?.first
        #expect(patch?["visibilities"] == nil)
        #expect(patch?["categories"] == nil)
        #expect(patch?["tags"] == .array([.object(["id": "tag"])]))
    }
    @Test func mediaUsesMappingIdentityAndPositionInsteadOfDuplicateURLs() {
        let original = product(["media": .array([
            .object(["id": "mapping-b", "mediaId": "image", "position": .int(2), "media": .object(["id": "image", "url": "https://internal.test/image.jpg"])]),
            .object(["id": "mapping-a", "mediaId": "image", "position": .int(1), "media": .object(["id": "image", "url": "https://internal.test/image.jpg"])]),
        ])])
        #expect(original.media.map(\.id) == ["mapping-a", "mapping-b"])
        #expect(original.media.allSatisfy { $0.url == "https://shop.test/image.jpg" })
    }
    @Test func failedSaveRetainsDraftAndDoesNotWriteUnchangedFields() async throws {
        let transport = ProductUITestTransport(arguments: ["--fail-save-once"])
        let api = api(transport), actions = ProductActions(api: api)
        await actions.loadPermissions()
        let original = ProductItem(try #require(try await api.repository("product").get("product-0")), shopURL: "https://product-ui.test")
        var draft = ProductGeneralDraft(original); draft.name = "Updated linen shirt"
        #expect(!(await actions.saveGeneral(original, draft: draft, fields: [])))
        #expect(draft.name == "Updated linen shirt" && actions.error != nil)
        #expect(try await api.repository("product").get(original.id)?.string("name") == original.name)
        #expect(await actions.saveGeneral(original, draft: draft, fields: []))
        let request = try #require(await transport.requests.last { $0.method == .patch })
        #expect(request.body.flatMap(JSONValue.parse) == .object(["name": "Updated linen shirt"]))
        let saved = try #require(try await api.repository("product").get(original.id))
        #expect(saved.json["customFields"] == original.raw["customFields"])
        #expect(saved.json["price"] == original.raw["price"])
        #expect(saved.json["description"] == original.raw["description"])
    }
    @Test func quickEditsPreserveUntouchedPricesAndRecoverFromSaveFailure() async throws {
        let transport = ProductUITestTransport(arguments: ["--fail-save-once"]), api = api(transport), actions = ProductActions(api: api)
        await actions.loadPermissions()
        let original = ProductItem(try #require(try await api.repository("product").get("product-0")), shopURL: "https://product-ui.test")
        let locale = Locale(identifier: "de_DE"), price = ProductPriceDraft(price: original.defaultPrice, locale: locale)
        #expect(!(await actions.saveQuick(original, stock: "45", active: original.active, price: price, locale: locale)))
        #expect(await actions.saveQuick(original, stock: "45", active: original.active, price: price, locale: locale))
        let request = try #require(await transport.requests.last { $0.method == .patch })
        #expect(request.body.flatMap(JSONValue.parse) == .object(["stock": .int(45)]))
    }
    @Test func uploadedMediaAttachmentRetriesWithoutUploadingTwice() async throws {
        let transport = ProductUITestTransport(arguments: ["--fail-attach-once"]), api = api(transport), actions = ProductActions(api: api)
        await actions.loadPermissions()
        let original = ProductItem(try #require(try await api.repository("product").get("product-0")), shopURL: "https://product-ui.test")
        #expect(!(await actions.uploadMedia(original, data: Data([1, 2, 3]), fileExtension: "png", fileName: "shirt", mimeType: "image/png", makeCover: true)))
        let uploadedID = try #require(actions.pendingMediaID)
        #expect(await actions.retryMediaAttachment(original))
        #expect(actions.pendingMediaID == nil)
        let saved = ProductItem(try #require(try await api.repository("product").get(original.id)), shopURL: "https://product-ui.test")
        #expect(saved.media.count == 2)
        #expect(saved.media.first { $0.id == saved.coverID }?.mediaID == uploadedID)
        let requests = await transport.requests
        #expect(requests.filter { $0.url.contains("/upload?") }.count == 1)
        #expect(requests.filter { $0.url.hasSuffix("/api/media") && $0.method == .post }.count == 1)
    }
    @Test func createsProductWithRequiredTaxPriceAndStock() async throws {
        let transport = ProductUITestTransport(), api = api(transport), actions = ProductActions(api: api)
        await actions.loadPermissions()
        var draft = ProductGeneralDraft(); draft.name = "New product"; draft.productNumber = "NEW-100"
        var price = ProductPriceDraft(price: nil, locale: Locale(identifier: "en_US")); price.gross = "119"; price.net = "100"
        #expect(await actions.create(id: "new-product", draft: draft, fields: [], taxID: "tax", price: price, stock: "5", locale: Locale(identifier: "en_US")))
        let saved = try #require(try await api.repository("product").get("new-product"))
        #expect(saved.string("taxId") == "tax" && saved.int("stock") == 5)
        #expect(saved.boolean("active") == false)
        #expect(saved.json["price"]?.arrayValue?.first?["currencyId"]?.stringValue == ShopwareDefaults.currencyID)
    }
    @Test func variantsArePagedBeyondOneHundredAndRetryTheSamePage() async {
        let transport = ProductUITestTransport(arguments: ["--fail-page-once"], variants: 132)
        let api = api(transport)
        let listing = ListingState(source: { try await api.repository("product").search($0) },
                                   baseCriteria: { productWorkspaceCriteria(parentID: "product-0") }, mapper: { ProductItem($0, shopURL: "https://product-ui.test") })
        listing.reload(); await listing.fetchTask?.value
        #expect(listing.total == 132 && listing.items.count == 25)
        listing.loadMore(); await listing.fetchTask?.value
        #expect(listing.error != nil && listing.items.count == 25)
        for _ in 0..<5 { listing.loadMore(); await listing.fetchTask?.value }
        #expect(listing.items.count == 132 && Set(listing.items.map(\.id)).count == 132)
        #expect(listing.items.allSatisfy { $0.parentID == "product-0" })
    }
    @Test func organizationRetriesAtomicallyAndPreservesVisibilityLevels() async throws {
        let transport = ProductUITestTransport(arguments: ["--fail-assignments-once"]), api = api(transport), actions = ProductActions(api: api)
        await actions.loadPermissions()
        let original = ProductItem(try #require(try await api.repository("product").get("product-0")), shopURL: "https://product-ui.test")
        var draft = ProductOrganizationDraft(original)
        draft.categories = ["new-category"]; draft.visibilities["outlet"] = 20
        #expect(!(await actions.saveOrganization(original, draft: draft)))
        #expect(try await api.repository("product").get(original.id)?.entities("categories").first?.id == "category")
        #expect(await actions.saveOrganization(original, draft: draft))
        let saved = ProductItem(try #require(try await api.repository("product").get(original.id)), shopURL: "https://product-ui.test")
        #expect(saved.references("categories").map(\.id) == ["new-category"])
        #expect(saved.visibilities.first { $0.salesChannelID == "channel" }?.visibility == 10)
        #expect(saved.visibilities.first { $0.salesChannelID == "outlet" }?.visibility == 20)
    }
    @Test func mediaAttachmentAndCoverRemovalKeepLibraryFiles() async throws {
        let transport = ProductUITestTransport(), api = api(transport), actions = ProductActions(api: api)
        await actions.loadPermissions()
        var original = ProductItem(try #require(try await api.repository("product").get("product-0")), shopURL: "https://product-ui.test")
        #expect(await actions.attachMedia(original, mediaIDs: ["image-2"]))
        original = ProductItem(try #require(try await api.repository("product").get(original.id)), shopURL: "https://product-ui.test")
        #expect(original.media.count == 2)
        let added = try #require(original.media.first { $0.mediaID == "image-2" })
        #expect(await actions.setCover(original, media: added))
        original = ProductItem(try #require(try await api.repository("product").get(original.id)), shopURL: "https://product-ui.test")
        #expect(original.coverID == added.id)
        #expect(await actions.removeMedia(original, media: added))
        let saved = ProductItem(try #require(try await api.repository("product").get(original.id)), shopURL: "https://product-ui.test")
        #expect(saved.media.count == 1 && saved.coverID == "media-mapping-0")
        #expect(try await api.repository("media").search(Criteria()).total == 3)
    }
    @Test func partialBulkDeletionKeepsOnlyFailuresForRetry() async {
        let transport = ProductUITestTransport(arguments: ["--fail-delete-product-2-once"]), actions = ProductActions(api: api(transport))
        await actions.loadPermissions()
        let succeeded = await actions.delete(ids: ["product-1", "product-2"])
        #expect(succeeded == ["product-1"] && actions.error != nil)
        #expect(await actions.delete(ids: Set(["product-1", "product-2"]).subtracting(succeeded)) == ["product-2"])
        #expect(await transport.requests.filter { $0.method == .delete && $0.url.hasSuffix("product-1") }.count == 1)
    }
    @Test func permissionsFailClosedAndCurrencyLoadingCanRetry() async {
        for flag in ["--read-only", "--editor-only", "--deleter-only", "--fail-permissions-once"] {
            let actions = ProductActions(api: api(ProductUITestTransport(arguments: [flag])))
            #expect(!actions.canEdit && !actions.canCreate && !actions.canDelete)
            await actions.loadPermissions()
            #expect(actions.canEdit == (flag == "--editor-only"))
            #expect(actions.canDelete == (flag == "--deleter-only"))
        }
        let actions = ProductActions(api: api(ProductUITestTransport(arguments: ["--fail-currency-once"])))
        await actions.loadPermissions()
        #expect(actions.currencyCode == nil && actions.currencyError != nil)
        await actions.loadCurrencies()
        #expect(actions.currencyCode == "EUR")
    }
}
