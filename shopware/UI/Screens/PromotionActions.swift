import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class PromotionActions {
    // Shopware Core Defaults::CURRENCY identifies the currency used by discount values.
    nonisolated static let systemCurrencyID = "b7d2554b0ce847cd82f3ac9bd1c0dfca"
    private(set) var currencyCode: String?
    private(set) var currencyError: String?
    let api: ShopApi
    private(set) var permissions = AdminPermissions()
    private(set) var permissionsError: String?
    private(set) var busy = false
    var error: String?
    init(api: ShopApi) { self.api = api }
    var canEdit: Bool { permissions.allows("promotion:update") && !busy }
    var canCreate: Bool { permissions.allows("promotion:create") && !busy }
    var canDelete: Bool { permissions.allows("promotion:delete") && !busy }
    var canGenerate: Bool { canEdit && permissions.allows("promotion_individual_code:create") }
    var canEditConditions: Bool {
        canEdit && ["promotion_sales_channel", "promotion_persona_rule", "promotion_cart_rule", "promotion_order_rule"].allSatisfy {
            permissions.allows("\($0):create") && permissions.allows("\($0):delete")
        }
    }
    func loadPermissions() async {
        do { permissions = try await api.permissions(); permissionsError = nil }
        catch { permissions = AdminPermissions(); permissionsError = error.localizedDescription }
        await loadCurrency()
    }
    func loadCurrency() async {
        currencyCode = nil; currencyError = nil
        guard permissions.allows("currency:read") else {
            currencyError = String(localized: "Currency information is unavailable."); return
        }
        do {
            guard let currency = try await api.repository("currency").get(Self.systemCurrencyID)?.string("isoCode"), !currency.isEmpty else {
                throw ApiError.notFound(message: String(localized: "Currency information is unavailable."))
            }
            currencyCode = currency
        } catch { currencyError = error.localizedDescription }
    }
    func save(id: String, draft: PromotionDraft, fields: [CustomerCustomFieldSet], creating: Bool) async -> Bool {
        guard creating ? canCreate : canEdit else { return false }
        if let validation = draft.validationError(sets: fields) { error = validation; return false }
        return await run {
            if creating {
                var payload = draft.payload
                payload.merge(["id": .string(id), "exclusive": false, "useSetGroups": false, "preventCombination": false]) { _, new in new }
                try await self.api.repository("promotion").create(.object(payload))
            } else { try await self.api.repository("promotion").patch(id, .object(draft.payload)) }
        }
    }
    func setActive(id: String, active: Bool) async -> Bool {
        guard canEdit else { return false }
        return await run { try await self.api.promotions.setActive(promotionId: id, active: active) }
    }
    func saveConditions(original: PromotionItem, draft: PromotionConditionsDraft) async -> Bool {
        guard canEditConditions else { return false }
        return await run { try await self.api.syncOperations(draft.operations(for: original)) }
    }
    func saveDiscount(promotion: PromotionItem, discount: PromotionDiscount?, id: String, draft: PromotionDiscountDraft, locale: Locale) async -> Bool {
        guard canEdit, currencyCode != nil, promotion.orderCount == 0,
              permissions.allows(discount == nil ? "promotion_discount:create" : "promotion_discount:update") else { return false }
        if let validation = draft.validationError(locale: locale) { error = validation; return false }
        return await run {
            try await self.requireUnusedPromotion(promotion.id)
            var payload = draft.payload(locale: locale, isNew: discount == nil)
            if discount == nil {
                payload["id"] = .string(id); payload["promotionId"] = .string(promotion.id)
                try await self.api.repository("promotion-discount").create(.object(payload))
            } else { try await self.api.repository("promotion-discount").patch(id, .object(payload)) }
        }
    }
    func deleteDiscount(promotion: PromotionItem, id: String) async -> Bool {
        guard canEdit, promotion.orderCount == 0, permissions.allows("promotion_discount:delete") else { return false }
        return await run { try await self.requireUnusedPromotion(promotion.id); try await self.api.repository("promotion-discount").delete(id) }
    }
    func generate(promotion: PromotionItem, amount: Int) async -> Bool {
        guard canGenerate, promotion.codeMode == .individual, (1...500).contains(amount) else { return false }
        return await run { try await self.api.promotions.addIndividualCodes(promotionId: promotion.id, amount: amount) }
    }
    func delete(ids: Set<String>) async -> Set<String> {
        guard canDelete, !ids.isEmpty else { return [] }
        busy = true; error = nil
        defer { busy = false }
        var succeeded = Set<String>(), failures: [String] = []
        for id in ids.sorted() {
            do { try await requireUnusedPromotion(id); try await api.repository("promotion").delete(id); succeeded.insert(id) }
            catch ApiError.notFound { succeeded.insert(id) }
            catch { failures.append(error.localizedDescription) }
        }
        if let first = failures.first { error = String(localized: "\(failures.count) promotions couldn't be deleted. Only the remaining promotions are selected.") + "\n" + first }
        return succeeded
    }
    private func requireUnusedPromotion(_ id: String) async throws {
        guard let entity = try await api.repository("promotion").get(id) else { throw ApiError.notFound(message: String(localized: "This promotion is no longer available.")) }
        if (entity.int("orderCount") ?? 0) > 0 {
            throw ApiError.unexpected(status: 409, message: String(localized: "Redeemed promotions cannot be deleted or have their discounts changed."))
        }
    }
    private func run(_ operation: () async throws -> Void) async -> Bool {
        busy = true; error = nil
        defer { busy = false }
        do { try await operation(); return true }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription; return false }
    }
}
