import Foundation
import Testing
import ShopwareAdminAPI
import ShopwareDomain

/// These tests deliberately require a disposable backend. They never silently skip.
struct BackendTests {
    private func api() throws -> ShopApi {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["CONTRACT_SHOP_URL"])
        // Restrict destructive fixture writes to the local CI service.
        let host = URL(string: url)?.host
        try #require(host == "127.0.0.1" || host == "localhost")
        return ShopApi(baseURL: url, auth: .password(
            username: try #require(environment["CONTRACT_USERNAME"]),
            password: try #require(environment["CONTRACT_PASSWORD"]), refreshToken: nil))
    }

    private func id() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }

    @Test func firstPromotionChannelPersistsAndExistingPriorityIsPreserved() async throws {
        let api = try api()
        let permissions = try await api.permissions()
        try #require(permissions.allows("promotion:create"))
        let channels = try await api.repository("sales-channel").search(Criteria().setLimit(1))
        let channelID = try #require(channels.data.first?.id)
        let promotionID = id(), mappingID = id()
        try await api.repository("promotion").create(.object([
            "id": .string(promotionID), "name": "CI contract promotion", "active": false,
            "priority": 1, "useCodes": false, "useIndividualCodes": false,
        ]))
        func save(isNew: Bool) async throws {
            try await api.syncOperations(["save-promotion": .object([
                "entity": "promotion", "action": "upsert", "payload": .array([.object([
                    "id": .string(promotionID), "salesChannels": .array([
                        PromotionApi.salesChannelMapping(id: mappingID, salesChannelID: channelID, isNew: isNew),
                    ]),
                ])]),
            ])])
        }
        try await save(isNew: true)
        let created = try await api.repository("promotion-sales-channel").get(mappingID)
        #expect(created?.int("priority") == 1)
        #expect(created?.string("salesChannelId") == channelID)
        try await api.repository("promotion-sales-channel").patch(mappingID, .object(["priority": 7]))
        try await save(isNew: false)
        let retained = try await api.repository("promotion-sales-channel").get(mappingID)
        #expect(retained?.int("priority") == 7)
        try await api.repository("promotion").delete(promotionID)
    }

    @Test func localizedProductPriceRoundTripsThroughTheDAL() async throws {
        let api = try api()
        let tax = try #require(try await api.repository("tax").search(Criteria().setLimit(1)).data.first)
        let taxID = try #require(tax.id)
        let locale = Locale(identifier: "de_DE")
        var draft = ProductPriceDraft(price: nil, locale: locale)
        draft.updateGross("119,00", taxRate: tax.double("taxRate"), locale: locale)
        let prices = try #require(draft.prices(replacing: [], locale: locale))
        let productID = id()
        try await api.repository("product").create(.object([
            "id": .string(productID), "name": "CI contract product", "productNumber": .string(productID),
            "stock": 0, "active": false, "taxId": .string(taxID), "price": .array(prices),
        ]))
        let stored = try #require(try await api.repository("product").get(productID))
        let price = try #require(stored.json["price"]?.arrayValue?.first)
        #expect(price["gross"]?.doubleValue == 119)
        #expect(price["currencyId"]?.stringValue == ShopwareDefaults.currencyID)
        try await api.repository("product").delete(productID)
    }

    @Test func mediaFolderLifecycleUsesProductionActions() async throws {
        let api = try api()
        let folderID = try await api.media.createFolder(name: "CI contract folder", parentId: nil)
        let folder = try #require(try await api.repository("media-folder").get(folderID))
        #expect(folder.string("name") == "CI contract folder")
        try await api.repository("media-folder").patch(folderID, .object(["name": "Renamed contract folder"]))
        let renamed = try await api.repository("media-folder").get(folderID)
        #expect(renamed?.string("name") == "Renamed contract folder")
        try await api.repository("media-folder").delete(folderID)
        let deleted = try await api.repository("media-folder").get(folderID)
        #expect(deleted == nil)
    }
}
