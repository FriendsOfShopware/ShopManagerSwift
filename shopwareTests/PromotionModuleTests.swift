import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct PromotionModuleTests {
    private func api(_ transport: PromotionUITestTransport) -> ShopApi {
        ShopApi(baseURL: "https://promotion-ui.test", auth: .refreshToken(token: "fixture"), transport: transport)
    }
    private func item(_ index: Int = 0) -> PromotionItem { PromotionItem(SwEntity(PromotionUITestTransport.promotion(index))) }
    private func listing(_ transport: PromotionUITestTransport) -> ListingState<PromotionItem> {
        let api = api(transport)
        return ListingState(filters: promotionFilters(), source: { try await api.repository("promotion").search($0) },
                            baseCriteria: { promotionListCriteria().addSorting("createdAt", "DESC") }, mapper: PromotionItem.init)
    }
    @Test func statusUsesScheduleBoundariesAndPreservesFractions() {
        let now = Date(timeIntervalSince1970: 100)
        var promotion = item()
        #expect(promotion.discounts.first?.value == 25.5)
        #expect(promotion.salesChannels.first?.mappingID == "mapping-0")
        promotion.validFrom = now.addingTimeInterval(1); #expect(promotion.state(at: now) == .scheduled)
        promotion.validFrom = now; #expect(promotion.state(at: now) == .active)
        promotion.validUntil = now; #expect(promotion.state(at: now) == .expired)
        promotion.active = false; #expect(promotion.state(at: now) == .inactive)
    }
    @Test func nameEditsPreservePreciseScheduleAndDiscountValues() {
        var raw = PromotionUITestTransport.promotion(0).objectValue!
        raw["validFrom"] = "2026-09-01T10:00:00.123Z"
        let original = PromotionItem(SwEntity(.object(raw)))
        var draft = PromotionDraft(original); draft.name = "Renamed"
        #expect(draft.payload["validFrom"] == "2026-09-01T10:00:00.123Z")
        let discount = PromotionDiscount(SwEntity(.object(["type": "percentage", "scope": "cart", "value": .number(25.123456789)])))
        let discountDraft = PromotionDiscountDraft(discount, locale: Locale(identifier: "de_DE"))
        #expect(discountDraft.payload(locale: Locale(identifier: "de_DE"), isNew: false)["value"] == .number(discount.value))
    }
    @Test func listingFiltersSearchPagesAndSortsOnServer() async {
        let transport = PromotionUITestTransport(count: 31), state = listing(transport)
        state.reload(); await state.fetchTask?.value
        #expect(state.total == 31 && state.items.count == 25)
        state.loadMore(); await state.fetchTask?.value
        #expect(state.items.count == 31 && Set(state.items.map(\.id)).count == 31)
        state.applyFilterValues(["active": .options(["true"]), "salesChannel": .options(["channel"]), "individual": .options(["true"]), "useCodes": .options(["true"])])
        await state.fetchTask?.value
        #expect(state.total == 11 && state.items.allSatisfy { $0.codeMode == .individual })
        state.applyFilterValues(["salesChannel": .options(["channel-2"])]); await state.fetchTask?.value; #expect(state.total == 0)
        state.applyFilterValues([:]); state.setTerm("Winter"); state.search(); await state.fetchTask?.value
        #expect(state.total == 10 && state.items.allSatisfy { !$0.active })
        state.setTerm(""); state.setSorting([ListingSort(field: "priority", ascending: false)]); await state.fetchTask?.value
        #expect(state.items.first?.priority == 31)
    }
    @Test func failedGeneralSaveRetainsDraftAndComplexSettings() async throws {
        let transport = PromotionUITestTransport(arguments: ["--fail-save-once"]), api = api(transport)
        let actions = PromotionActions(api: api); await actions.loadPermissions()
        let original = item(); var draft = PromotionDraft(original)
        draft.name = "Updated campaign"; draft.globalLimit = ""; draft.customFields["promotion_reference"] = "NEW"
        #expect(!(await actions.save(id: original.id, draft: draft, fields: [], creating: false)))
        #expect(actions.error != nil && draft.name == "Updated campaign")
        #expect(await actions.save(id: original.id, draft: draft, fields: [], creating: false))
        let saved = PromotionItem(try #require(try await api.repository("promotion").get(original.id)))
        #expect(saved.name == draft.name && saved.maxRedemptionsGlobal == nil)
        #expect(saved.discounts == original.discounts && saved.salesChannels == original.salesChannels)
        #expect(saved.customFields["unexposed"] == "preserved")
        let requests = await transport.requests
        let patch = try #require(requests.last { $0.method == .patch }?.body.flatMap(JSONValue.parse)?.objectValue)
        #expect(patch["discounts"] == nil && patch["orderCount"] == nil && patch["salesChannels"] == nil)
    }
    @Test func generalValidationRejectsBadDatesLimitsAndCodes() {
        var draft = PromotionDraft(); #expect(draft.validationError(sets: []) != nil)
        draft.name = "Campaign"; #expect(draft.validationError(sets: []) == nil)
        draft.priority = "1.5"; #expect(draft.validationError(sets: []) != nil); draft.priority = "0"
        draft.globalLimit = "-1"; #expect(draft.validationError(sets: []) != nil); draft.globalLimit = ""
        draft.hasStart = true; draft.hasEnd = true; draft.ends = draft.starts; #expect(draft.validationError(sets: []) != nil)
        draft.hasEnd = false; draft.codeMode = .fixed; #expect(draft.validationError(sets: []) != nil)
        draft.code = "WELCOME"; #expect(draft.validationError(sets: []) == nil)
        draft.codeMode = .individual; draft.codePattern = "SAME"; #expect(draft.validationError(sets: []) != nil)
        draft.codePattern = "PROMO-%s%d%s%d"; #expect(draft.validationError(sets: []) == nil)
    }
    @Test func createsInactivePromotionThenUpdatesActivation() async throws {
        let transport = PromotionUITestTransport(), api = api(transport), actions = PromotionActions(api: api)
        await actions.loadPermissions(); var draft = PromotionDraft(); draft.name = "New campaign"
        #expect(await actions.save(id: "new-promotion", draft: draft, fields: [], creating: true))
        #expect(try await api.repository("promotion").get("new-promotion")?.boolean("active") == false)
        #expect(await actions.setActive(id: "new-promotion", active: true))
        #expect(try await api.repository("promotion").get("new-promotion")?.boolean("active") == true)
    }
    @Test func conditionMappingChangesAreAtomicAndRetryStable() async throws {
        let transport = PromotionUITestTransport(arguments: ["--fail-conditions-once"]), api = api(transport), actions = PromotionActions(api: api)
        await actions.loadPermissions(); let original = item(); var draft = PromotionConditionsDraft(original)
        draft.salesChannels = ["channel-2"]; draft.personaRules = ["rule"]; draft.preventCombination = true; draft.exclusions = [original.id, "promotion-1"]
        #expect(draft.operations(for: original) == draft.operations(for: original))
        #expect(!(await actions.saveConditions(original: original, draft: draft)))
        #expect(PromotionItem(try #require(try await api.repository("promotion").get(original.id))).salesChannels == original.salesChannels)
        #expect(await actions.saveConditions(original: original, draft: draft))
        let saved = PromotionItem(try #require(try await api.repository("promotion").get(original.id)))
        #expect(saved.salesChannels.map(\.id) == ["channel-2"] && saved.personaRules.map(\.id) == ["rule"])
        #expect(saved.exclusionIDs == ["promotion-1"] && saved.discounts == original.discounts)
        let requests = await transport.requests
        let sync = try #require(requests.last { $0.url.hasSuffix("/_action/sync") })
        #expect(sync.headers["single-operation"] == "1")
        #expect(sync.body.flatMap(JSONValue.parse)?["remove-sales-channels"]?["payload"] == .array([.object(["id": "mapping-0"])]))
    }
    @Test func restrictsIncompatibleRulesWithoutRemovingExistingSelections() {
        #expect(PromotionRuleCompatibility.allows(SwEntity(PromotionUITestTransport.rules[0]), customer: true))
        #expect(!PromotionRuleCompatibility.allows(SwEntity(PromotionUITestTransport.rules[1]), customer: false))
        let unknown = SwEntity(.object(["conditions": .array([.object(["type": "pluginUnknown"])])]))
        #expect(!PromotionRuleCompatibility.allows(unknown, customer: false))
    }
    @Test func assignsFirstSalesChannelWithRequiredPriorityAndPreservesExistingPriority() async throws {
        let transport = PromotionUITestTransport(arguments: ["--unassigned-promotion"])
        let api = api(transport), actions = PromotionActions(api: api)
        await actions.loadPermissions()
        let original = PromotionItem(try #require(try await api.repository("promotion").get("promotion-0")))
        #expect(original.salesChannels.isEmpty)
        var draft = PromotionConditionsDraft(original)
        draft.salesChannels = ["channel"]
        #expect(await actions.saveConditions(original: original, draft: draft))
        let saved = try #require(try await api.repository("promotion").get(original.id))
        #expect(saved.entities("salesChannels").first?.int("priority") == 1)
        #expect(saved.entities("salesChannels").first?.string("salesChannelId") == "channel")

        // Retrying from the same draft must reuse the mapping rather than add another.
        #expect(await actions.saveConditions(original: original, draft: draft))
        #expect(try await api.repository("promotion").get(original.id)?.entities("salesChannels").count == 1)

        let assigned = item(1)
        var updated = PromotionConditionsDraft(assigned)
        updated.preventCombination = true
        #expect(await actions.saveConditions(original: assigned, draft: updated))
        let unchangedChannel = try #require(try await api.repository("promotion").get(assigned.id)).entities("salesChannels").first
        #expect(unchangedChannel?.int("priority") == 7)
    }
    @Test func discountValidationIsLocaleAwareAndPreservesAdvancedFields() async throws {
        let transport = PromotionUITestTransport(), actions = PromotionActions(api: api(transport)), locale = Locale(identifier: "de_DE")
        await actions.loadPermissions(); let promotion = item(), discount = try #require(promotion.discounts.first)
        var draft = PromotionDiscountDraft(discount, locale: locale)
        #expect(draft.value == "25,5")
        draft.value = "30,75"; #expect(draft.validationError(locale: locale) == nil)
        #expect(Set(draft.payload(locale: locale, isNew: false).keys) == ["value", "maxValue"])
        #expect(await actions.saveDiscount(promotion: promotion, discount: discount, id: discount.id, draft: draft, locale: locale))
        var zero = draft; zero.type = "fixed"; zero.scope = "delivery"; zero.value = "0"
        #expect(zero.validationError(locale: locale) == nil)
        draft.value = "100,1"; #expect(draft.validationError(locale: locale) != nil)
        draft.value = "12.5"; #expect(draft.validationError(locale: locale) != nil)
        draft.value = "1,2,3"; #expect(draft.validationError(locale: locale) != nil)
    }
    @Test func permissionsFailClosedAndRolesRemainIndependent() async {
        for argument in ["--read-only", "--editor-only", "--deleter-only", "--fail-permissions-once"] {
            let actions = PromotionActions(api: api(PromotionUITestTransport(arguments: [argument])))
            #expect(!actions.canEdit && !actions.canDelete && !actions.canCreate)
            await actions.loadPermissions()
            #expect(actions.canEdit == (argument == "--editor-only"))
            #expect(actions.canDelete == (argument == "--deleter-only"))
            if argument == "--fail-permissions-once" { await actions.loadPermissions(); #expect(actions.canEdit && actions.canCreate) }
        }
    }
    @Test func redeemedPromotionsCannotBeDeletedOrDiscountedEvenWithStaleState() async throws {
        let transport = PromotionUITestTransport(), actions = PromotionActions(api: api(transport))
        await actions.loadPermissions(); var used = item(1); used.orderCount = 0
        let discount = try #require(used.discounts.first)
        #expect(!(await actions.saveDiscount(promotion: used, discount: discount, id: discount.id, draft: PromotionDiscountDraft(discount, locale: .current), locale: .current)))
        #expect(await actions.delete(ids: [used.id]) == [])
        #expect(!(await transport.requests).contains { $0.method == .delete || $0.method == .patch })
    }
    @Test func monetaryDiscountsUseTheServerCurrencyAndWaitForItToLoad() async throws {
        let transport = PromotionUITestTransport(arguments: ["--usd-currency", "--fail-currency-once"]), actions = PromotionActions(api: api(transport))
        await actions.loadPermissions(); #expect(actions.currencyCode == nil && actions.currencyError != nil)
        let promotion = item(), discount = try #require(promotion.discounts.first)
        #expect(!(await actions.saveDiscount(promotion: promotion, discount: discount, id: discount.id, draft: PromotionDiscountDraft(discount, locale: .current), locale: .current)))
        await actions.loadCurrency(); #expect(actions.currencyCode == "USD" && actions.currencyError == nil)
    }
    @Test func partialDeletionRetriesOnlyRemainingIDs() async {
        let transport = PromotionUITestTransport(arguments: ["--fail-delete-promotion-2-once"]), actions = PromotionActions(api: api(transport))
        await actions.loadPermissions(); let selected: Set<String> = ["promotion-0", "promotion-2"]
        let deleted = await actions.delete(ids: selected); #expect(deleted == ["promotion-0"] && actions.error != nil)
        #expect(await actions.delete(ids: selected.subtracting(deleted)) == ["promotion-2"])
        #expect((await transport.requests).filter { $0.method == .delete && $0.url.hasSuffix("/promotion-0") }.count == 1)
    }
    @Test func codesAreScopedPagedAndGenerationCanRetry() async throws {
        let transport = PromotionUITestTransport(arguments: ["--fail-generate-once"]), api = api(transport), actions = PromotionActions(api: api)
        await actions.loadPermissions(); let promotion = item()
        #expect(!(await actions.generate(promotion: promotion, amount: 7)))
        #expect(await actions.generate(promotion: promotion, amount: 7))
        let codes = try await api.repository("promotion-individual-code").search(promotionCodeCriteria(promotion.id).setPage(2).setLimit(25).setTotalCountMode(.exact))
        #expect(codes.total == 37 && codes.data.count == 12)
        let redeemed = try await api.repository("promotion-individual-code").search(promotionCodeCriteria(promotion.id).addFilter(Criteria.not("and", Criteria.equals("payload", nil))))
        #expect(redeemed.data.count == 1 && PromotionCode(redeemed.data[0]).customerName == "Alexandra Montgomery")
        #expect(!(await actions.generate(promotion: item(1), amount: 7)))
        #expect(!(await actions.generate(promotion: promotion, amount: 501)))
    }
}
