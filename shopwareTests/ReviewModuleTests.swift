import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct ReviewModuleTests {
    private let shop = ConnectedShop(id: "reviews", name: "Test", baseUrl: "https://review-ui.test")
    private func api(_ transport: ReviewUITestTransport) -> ShopApi {
        ShopApi(baseURL: "https://review-ui.test", auth: .refreshToken(token: "fixture"), transport: transport)
    }
    private func listing(_ transport: ReviewUITestTransport) -> ListingState<ReviewItem> {
        let api = api(transport)
        return ListingState(filters: reviewFilters(), source: { try await api.repository("product-review").search($0) },
                            baseCriteria: { reviewCriteria().addSorting("status").addSorting("createdAt", "DESC") }, mapper: ReviewItem.init)
    }

    @Test func preservesFractionalRatingsExternalReviewersAndMissingDates() {
        var raw = ReviewUITestTransport.review(0).objectValue!
        let review = ReviewItem(SwEntity(.object(raw)))
        #expect(review.points == 4.5)
        #expect(review.reviewer == "Alexandra Montgomery")
        #expect(review.productName == "Linen shirt · Sand")
        raw["createdAt"] = .null; raw["customer"] = .null; raw["product"] = .null
        let external = ReviewItem(SwEntity(.object(raw)))
        #expect(external.createdAt == nil)
        #expect(external.email == "guest@example.test")
        #expect(external.reviewer == "Guest reviewer")
        #expect(external.customerId == nil && external.productId == nil)
    }

    @Test func listingSupportsAllSixFiltersSearchPaginationAndServerSorting() async throws {
        let transport = ReviewUITestTransport(count: 31), state = listing(transport)
        state.reload(); await state.fetchTask?.value
        #expect(state.total == 31 && state.items.count == 25)
        #expect(state.items.first?.approved == false)
        state.loadMore(); await state.fetchTask?.value
        #expect(state.items.count == 31 && Set(state.items.map(\.id)).count == 31)
        state.applyFilterValues(["salesChannel": .options(["channel"]), "product": .options(["product"]), "customer": .options(["customer"]),
                                 "language": .options(["en"]), "status": .options(["false"]), "points": .range(min: 4, max: 4.5)])
        await state.fetchTask?.value
        #expect(state.total == 11 && state.items.allSatisfy { $0.points == 4.5 && !$0.approved })
        state.applyFilterValues(["language": .options(["de"])]); await state.fetchTask?.value
        #expect(state.total == 0)
        state.applyFilterValues([:]); state.setTerm("Color differs"); state.search(); await state.fetchTask?.value
        #expect(state.total == 10 && state.items.allSatisfy { $0.points == 2 })
        state.setTerm(""); state.setSorting([ListingSort(field: "points", ascending: false)]); await state.fetchTask?.value
        #expect(state.items.first?.points == 5)
        let requests = await transport.requests
        let request = try #require(requests.first { $0.url.hasSuffix("/search/product-review") })
        #expect(request.headers["sw-inheritance"] == "true")
        let body = try #require(request.body.flatMap(JSONValue.parse))
        #expect(Set(body["associations"]?.objectValue?.keys.map { $0 } ?? []) == ["customer", "product", "salesChannel", "language"])
    }

    @Test func approvalRefreshesAllAndFilteredListsWithoutStaleStatus() async {
        let transport = ReviewUITestTransport(), state = listing(transport), actions = ReviewActions(api: api(transport))
        await actions.loadPermissions(); state.reload(); await state.fetchTask?.value
        #expect(await actions.approve(id: "review-0", approved: true))
        state.reload(); await state.fetchTask?.value
        #expect(state.items.first { $0.id == "review-0" }?.approved == true)
        state.setFilterValue("status", .options(["false"])); await state.fetchTask?.value
        #expect(!state.items.contains { $0.id == "review-0" })
        #expect(await actions.approve(id: "review-0", approved: false))
        state.reload(); await state.fetchTask?.value
        #expect(state.items.contains { $0.id == "review-0" })
    }

    @Test func savesOnlyModerationFieldsAndRetainsDraftAfterFailure() async throws {
        let transport = ReviewUITestTransport(arguments: ["--fail-save-once"])
        let model = ReviewDetailViewModel(api: api(transport), shop: shop, reviewID: "review-0")
        await model.load()
        var draft = ReviewDraft(try #require(model.review))
        draft.comment = "Thank you for your detailed feedback."; draft.languageId = "de"; draft.approved = true
        draft.customFields["review_reference"] = .null
        #expect(!(await model.actions.save(id: "review-0", draft: draft, sets: model.fields)))
        #expect(model.actions.error != nil && draft.comment == "Thank you for your detailed feedback.")
        #expect(await model.actions.save(id: "review-0", draft: draft, sets: model.fields))
        await model.load()
        #expect(model.review?.comment == draft.comment && model.review?.languageName == "Deutsch")
        #expect(model.review?.approved == true)
        #expect(model.review?.customFields["unexposed"] == "preserved")
        let requests = await transport.requests
        let payload = try #require(requests.last { $0.method == .patch }?.body.flatMap(JSONValue.parse))
        #expect(Set(payload.objectValue!.keys) == ["status", "languageId", "comment", "customFields"])
        #expect(payload["customFields"]?["review_reference"] == .null)
        draft.comment = ""; #expect(await model.actions.save(id: "review-0", draft: draft, sets: model.fields))
        await model.load(); #expect(model.review?.hasReply == false)
    }

    @Test func invalidLanguageAndRequiredCustomFieldsNeverWrite() async throws {
        let transport = ReviewUITestTransport(), actions = ReviewActions(api: api(transport))
        await actions.loadPermissions()
        var draft = ReviewDraft(ReviewItem(SwEntity(ReviewUITestTransport.review(0))))
        draft.languageId = ""
        #expect(!(await actions.save(id: "review-0", draft: draft, sets: [])))
        #expect(actions.error != nil)
        draft.languageId = "en"
        let field = CustomerCustomField(SwEntity(.object(["id": "field", "name": "required", "type": "text", "config": .object(["required": true, "label": .object(["en-GB": "Required field"])])])), locale: "en-GB")
        let sets = [CustomerCustomFieldSet(id: "set", label: "Set", fields: [field])]
        #expect(!(await actions.save(id: "review-0", draft: draft, sets: sets)))
        #expect(await transport.requests.filter { $0.method == .patch }.isEmpty)
    }

    @Test func permissionsFailClosedAndEditorDeleterRemainIndependent() async {
        for flag in ["--read-only", "--fail-permissions-once", "--editor-only", "--deleter-only"] {
            let transport = ReviewUITestTransport(arguments: [flag]), actions = ReviewActions(api: api(transport))
            await actions.loadPermissions()
            #expect(actions.canEdit == (flag == "--editor-only"))
            #expect(actions.canDelete == (flag == "--deleter-only"))
            if !actions.canEdit { #expect(!(await actions.approve(id: "review-0", approved: true))) }
            if !actions.canDelete { #expect(await actions.delete(ids: ["review-0"]) == []) }
            #expect(await transport.requests.filter { $0.method == .patch || $0.method == .delete }.isEmpty)
            if flag == "--fail-permissions-once" { await actions.loadPermissions(); #expect(actions.canEdit && actions.canDelete) }
        }
    }

    @Test func partialDeleteRetriesOnlyFailuresAndHandlesAlreadyDeleted() async {
        let transport = ReviewUITestTransport(arguments: ["--fail-delete-review-1-once"]), actions = ReviewActions(api: api(transport))
        await actions.loadPermissions()
        var remaining: Set<String> = ["review-0", "review-1", "review-2"]
        let succeeded = await actions.delete(ids: remaining)
        #expect(succeeded == ["review-0", "review-2"] && actions.error != nil)
        remaining.subtract(succeeded)
        #expect(await actions.delete(ids: remaining) == ["review-1"])
        #expect(await transport.reviews.isEmpty)
        let deletes = await transport.requests.filter { $0.method == .delete }
        #expect(deletes.filter { $0.url.hasSuffix("review-0") }.count == 1)
        #expect(await actions.delete(ids: ["review-0"]) == ["review-0"])
    }

    @Test func loadFailuresRetryAndMissingReviewDoesNotFabricateData() async {
        let transport = ReviewUITestTransport(arguments: ["--fail-list-once", "--fail-detail-once", "--fail-fields-once"]), state = listing(transport)
        state.reload(); await state.fetchTask?.value; #expect(state.error != nil)
        state.reload(); await state.fetchTask?.value; #expect(state.error == nil && state.total == 3)
        let model = ReviewDetailViewModel(api: api(transport), shop: shop, reviewID: "review-0")
        await model.load(); #expect(model.error != nil && model.review == nil)
        await model.load(); #expect(model.review != nil && model.fieldsError != nil)
        await model.loadFields(); #expect(model.fieldsError == nil && model.fields.count == 1)
        _ = await model.actions.delete(ids: ["review-0"])
        await model.load(); #expect(model.error != nil && model.review == nil)
    }
}
