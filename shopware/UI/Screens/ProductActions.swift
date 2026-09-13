import ShopwareDomain
import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class ProductActions {
    let api: ShopApi
    private(set) var permissions = AdminPermissions()
    private(set) var permissionsError: String?
    private(set) var currencies: [ProductCurrency] = []
    private(set) var currencyError: String?
    private(set) var busy = false
    private(set) var pendingMediaID: String?
    @ObservationIgnored private var pendingMediaIsCover = false
    var error: String?
    init(api: ShopApi) { self.api = api }
    var currencyCode: String? { currencies.first { $0.id == ShopwareDefaults.currencyID }?.code }
    var canEdit: Bool { permissions.allows("product:update") && !busy }
    var canCreate: Bool { permissions.allows("product:create") && !busy }
    var canDelete: Bool { permissions.allows("product:delete") && !busy }
    var canEditOrganization: Bool {
        canEdit && ["product_category", "product_property", "product_tag", "product_visibility"].allSatisfy {
            permissions.allows($0 + ":create") && permissions.allows($0 + ":delete")
        }
    }
    var canAddMedia: Bool { canEdit && permissions.allows("product_media:create") }
    var canRemoveMedia: Bool { canEdit && permissions.allows("product_media:delete") }
    var canUpload: Bool { canAddMedia && permissions.allows("media:create") && permissions.allows("media:update") }

    func loadPermissions() async {
        do { permissions = try await api.permissions(); permissionsError = nil }
        catch { permissions = AdminPermissions(); permissionsError = error.localizedDescription }
        await loadCurrencies()
    }
    func loadCurrencies() async {
        currencyError = nil
        guard permissions.allows("currency:read") else {
            currencies = []; currencyError = String(localized: "Currency information is unavailable."); return
        }
        do {
            var rows: [ProductCurrency] = [], page = 1
            while true {
                let result = try await api.repository("currency").search(Criteria().setPage(page).setLimit(100).setTotalCountMode(.exact).addSorting("id"))
                rows += result.data.map(ProductCurrency.init)
                if rows.count >= result.total || result.data.isEmpty { break }
                page += 1
            }
            guard rows.contains(where: { $0.id == ShopwareDefaults.currencyID && !$0.code.isEmpty }) else {
                throw ApiError.notFound(message: String(localized: "Currency information is unavailable."))
            }
            currencies = rows
        } catch { currencies = []; currencyError = error.localizedDescription }
    }
    func saveGeneral(_ original: ProductItem, draft: ProductGeneralDraft, fields: [CustomerCustomFieldSet]) async -> Bool {
        guard canEdit else { return false }
        if let validation = draft.validationError(fields: fields) { error = validation; return false }
        let patch = draft.payload(comparedTo: ProductGeneralDraft(original))
        guard !patch.isEmpty else { return true }
        return await run { try await self.api.repository("product").patch(original.id, .object(patch)) }
    }
    func saveInventory(_ original: ProductItem, draft: ProductInventoryDraft, locale: Locale) async -> Bool {
        guard canEdit else { return false }
        if let validation = draft.validationError(locale: locale) { error = validation; return false }
        let patch = draft.payload(comparedTo: ProductInventoryDraft(original, locale: locale), locale: locale)
        guard !patch.isEmpty else { return true }
        return await run { try await self.api.repository("product").patch(original.id, .object(patch)) }
    }
    func savePrice(_ original: ProductItem, draft: ProductPriceDraft, locale: Locale) async -> Bool {
        guard canEdit, currencyCode != nil else { return false }
        if let validation = draft.validationError(locale: locale) { error = validation; return false }
        guard let prices = draft.prices(replacing: original.prices, locale: locale) else { return false }
        return await run { try await self.api.repository("product").patch(original.id, .object(["price": .array(prices)])) }
    }
    func saveQuick(_ original: ProductItem, stock: String, active: Bool, price: ProductPriceDraft?, locale: Locale) async -> Bool {
        guard canEdit else { return false }
        guard let stock = ProductNumberInput.integer(stock) else { error = String(localized: "Enter a valid stock quantity."); return false }
        var patch: [String: JSONValue] = [:]
        if stock != original.stock { patch["stock"] = .int(stock) }
        if active != original.active { patch["active"] = .bool(active) }
        if let price, price != ProductPriceDraft(price: original.defaultPrice, locale: locale) {
            guard currencyCode != nil else { return false }
            if let validation = price.validationError(locale: locale) { error = validation; return false }
            guard let prices = price.prices(replacing: original.prices, locale: locale) else { return false }
            patch["price"] = .array(prices)
        }
        guard !patch.isEmpty else { return true }
        return await run { try await self.api.repository("product").patch(original.id, .object(patch)) }
    }
    func saveOrganization(_ original: ProductItem, draft: ProductOrganizationDraft) async -> Bool {
        guard canEditOrganization, !original.isVariant, draft.visibilities.values.allSatisfy({ [10, 20, 30].contains($0) }) else { return false }
        return await run { try await self.api.syncOperations(draft.operations(for: original)) }
    }
    func create(id: String, draft: ProductGeneralDraft, fields: [CustomerCustomFieldSet], taxID: String, price: ProductPriceDraft, stock: String, locale: Locale) async -> Bool {
        guard canCreate, currencyCode != nil else { return false }
        if let validation = draft.validationError(fields: fields) ?? price.validationError(locale: locale) { error = validation; return false }
        guard !taxID.isEmpty, let stock = ProductNumberInput.integer(stock), let prices = price.prices(replacing: [], locale: locale) else {
            error = String(localized: "Select a tax rate and enter a valid stock quantity."); return false
        }
        var payload = draft.payload(comparedTo: nil)
        payload.merge(["id": .string(id), "taxId": .string(taxID), "stock": .int(stock), "price": .array(prices)]) { _, new in new }
        return await run { try await self.api.repository("product").create(.object(payload)) }
    }
    func setActive(ids: Set<String>, active: Bool) async -> Set<String> {
        guard canEdit else { return [] }
        return await batch(ids) { try await self.api.repository("product").patch($0, .object(["active": .bool(active)])) }
    }
    func delete(ids: Set<String>) async -> Set<String> {
        guard canDelete else { return [] }
        return await batch(ids) { id in
            do { try await self.api.repository("product").delete(id) }
            catch ApiError.notFound { } // An already-deleted row is a successful retry.
        }
    }
    func attachMedia(_ product: ProductItem, mediaIDs: Set<String>) async -> Bool {
        guard canAddMedia, !product.isVariant else { return false }
        let additions = mediaIDs.subtracting(product.media.map(\.mediaID)).sorted()
        guard !additions.isEmpty else { return true }
        let start = (product.media.map(\.position).max() ?? -1) + 1
        let media = additions.enumerated().map { offset, id -> JSONValue in
            .object(["id": .string(ProductOrganizationDraft.mappingID(productID: product.id, relation: "media", targetID: id)), "mediaId": .string(id), "position": .int(start + offset)])
        }
        var patch: [String: JSONValue] = ["media": .array(media)]
        if product.coverID == nil { patch["coverId"] = media.first?["id"] }
        return await run { try await self.api.repository("product").patch(product.id, .object(patch)) }
    }
    func setCover(_ product: ProductItem, media: ProductMediaItem) async -> Bool {
        guard canEdit, !product.isVariant, product.media.contains(where: { $0.id == media.id }) else { return false }
        return await run { try await self.api.repository("product").patch(product.id, .object(["coverId": .string(media.id)])) }
    }
    func uploadMedia(_ product: ProductItem, data: Data, fileExtension: String, fileName: String?, mimeType: String, makeCover: Bool = false) async -> Bool {
        guard canUpload, !product.isVariant, pendingMediaID == nil else { return false }
        return await run {
            self.pendingMediaIsCover = makeCover
            self.pendingMediaID = try await self.api.media.upload(bytes: data, extension: fileExtension, fileName: fileName, mimeType: mimeType)
            try await self.attachPendingMedia(product.id)
        }
    }
    func retryMediaAttachment(_ product: ProductItem) async -> Bool {
        guard canAddMedia, !product.isVariant, pendingMediaID != nil else { return false }
        return await run { try await self.attachPendingMedia(product.id) }
    }
    private func attachPendingMedia(_ productID: String) async throws {
        guard let mediaID = pendingMediaID else { return }
        guard let current = try await api.repository("product").get(productID, criteria: productWorkspaceDetailCriteria()) else { throw ApiError.notFound(message: String(localized: "This product is no longer available.")) }
        let product = ProductItem(current, shopURL: "")
        let mappingID = ProductOrganizationDraft.mappingID(productID: productID, relation: "media", targetID: mediaID)
        var patch: [String: JSONValue] = ["media": .array([.object(["id": .string(mappingID), "mediaId": .string(mediaID), "position": .int((product.media.map(\.position).max() ?? -1) + 1)])])]
        if product.coverID == nil || pendingMediaIsCover { patch["coverId"] = .string(mappingID) }
        try await api.repository("product").patch(productID, .object(patch))
        pendingMediaID = nil
    }
    func removeMedia(_ product: ProductItem, media: ProductMediaItem) async -> Bool {
        guard canRemoveMedia, !product.isVariant, product.media.contains(where: { $0.id == media.id }) else { return false }
        var operations: [String: JSONValue] = ["remove-media": .object(["entity": "product_media", "action": "delete", "payload": .array([.object(["id": .string(media.id), "versionId": .string(ShopwareDefaults.liveVersionID)])])])]
        if product.coverID == media.id {
            let next = product.media.first { $0.id != media.id }?.id
            operations["save-product"] = .object(["entity": "product", "action": "upsert", "payload": .array([.object(["id": .string(product.id), "coverId": next.map(JSONValue.string) ?? .null])])])
        }
        return await run { try await self.api.syncOperations(operations) }
    }
    private func batch(_ ids: Set<String>, operation: (String) async throws -> Void) async -> Set<String> {
        busy = true; error = nil
        defer { busy = false }
        var succeeded = Set<String>(), failures: [String] = []
        for id in ids.sorted() {
            do { try await operation(id); succeeded.insert(id) }
            catch { failures.append(error.localizedDescription) }
        }
        if let first = failures.first { error = String(localized: "\(failures.count) products couldn't be updated. Only the remaining products are selected.") + "\n" + first }
        return succeeded
    }
    private func run(_ operation: () async throws -> Void) async -> Bool {
        busy = true; error = nil
        defer { busy = false }
        do { try await operation(); return true }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription; return false }
    }
}
