import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct OrderModuleTests {
    private func model(_ transport: OrderUITestTransport) -> OrderDetailViewModel {
        let shop = ConnectedShop(id: "test", name: "Test", baseUrl: "https://order-ui.test")
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        return OrderDetailViewModel(repo: repo, shop: shop, orderId: "order-0")
    }

    @Test func parsesStableRecordsAllPaymentsAndFractionalNegativeTaxes() async throws {
        var source = OrderUITestTransport.order(0).objectValue!
        source["transactions"] = .array([
            .object(["id": "failed", "stateMachineState": .object(["technicalName": "failed"]), "createdAt": "2026-09-11T12:00:00Z"]),
            .object(["id": "active", "stateMachineState": .object(["technicalName": "open"]), "createdAt": "2026-09-11T11:00:00Z"]),
        ])
        source["price"] = .object(["calculatedTaxes": .array([
            .object(["taxRate": 7.7, "tax": 10]), .object(["taxRate": 7.7, "tax": -2]), .object(["taxRate": 19, "tax": 3])])])
        let first = parseOrderDetail(SwEntity(.object(source))), second = parseOrderDetail(SwEntity(.object(source)))
        #expect(first == second)
        #expect(first.payments.map(\.id) == ["failed", "active"])
        #expect(first.payments.first(where: \.primary)?.id == "active")
        #expect(first.taxes == [TaxLine(rate: 7.7, amount: 8), TaxLine(rate: 19, amount: 3)])
        #expect(first.lineItems.first?.id == "item")
        #expect(first.documents.first?.number == "INV-10001")
        #expect(first.customerId == "customer")
    }

    @Test func payloadWritesOnlyChangesAndExplicitlyClearsCustomFields() async throws {
        var original = parseOrderDetail(SwEntity(OrderUITestTransport.order(0)))
        original.customFields = ["clearMe": "previous", "keepMe": 42]
        var draft = original
        #expect(orderEditPayload(draft: draft, original: original) == .object([:]))
        draft.customFields.removeValue(forKey: "clearMe")
        draft.lineItems[0].quantity = 3
        draft.lineItems[0].unitPrice = 55
        draft.internalComment = ""
        let payload = orderEditPayload(draft: draft, original: original)
        #expect(payload["customFields"] == .object(["clearMe": .null]))
        #expect(payload["internalComment"] == .null)
        #expect(payload["lineItems"]?.arrayValue?.first?["quantity"] == 3)
        #expect(payload["lineItems"]?.arrayValue?.first?["priceDefinition"]?["price"] == 55)
        #expect(payload["lineItems"]?.arrayValue?.first?["priceDefinition"]?["quantity"] == 3)
        #expect(payload["addresses"] == nil && payload["orderCustomer"] == nil)
    }

    @Test func versionReviewAndSaveNeverMutateLiveUntilConfirmed() async throws {
        let transport = OrderUITestTransport(), owner = model(transport)
        await owner.load()
        let edit = OrderEditModel(owner: owner)
        await edit.start()
        #expect(edit.ready)
        edit.draft?.internalComment = "New internal note"
        #expect(!edit.reviewed && edit.canSave)
        #expect(await edit.save() == false)
        #expect(edit.reviewed)
        #expect(await transport.live.first?["internalComment"] == "Pack with care.")
        #expect(await edit.save())
        #expect(owner.detail?.internalComment == "New internal note")
        #expect(await transport.drafts.isEmpty)
    }

    @Test func validationFailureKeepsDraftAndNeverMergesBeforeSuccessfulReview() async throws {
        let transport = OrderUITestTransport(arguments: ["--fail-recalculate-once"]), owner = model(transport)
        await owner.load()
        let edit = OrderEditModel(owner: owner)
        await edit.start()
        edit.setQuantity(id: "item", quantity: 3)
        await edit.review()
        #expect(edit.issues.first?.blocksOrder == true && !edit.reviewed)
        #expect(edit.draft?.lineItems.first?.quantity == 3)
        #expect(await transport.requests.filter { $0.url.contains("/version/merge/") }.isEmpty)
        await edit.review()
        #expect(edit.reviewed && edit.issues.isEmpty)
        #expect(edit.draft?.amountTotal == 153.4)
        #expect(await edit.discard())
        #expect(owner.detail?.amountTotal == 103.9)
        #expect(await transport.drafts.isEmpty)
    }

    @Test func failedSavePreservesUnsentDraftForRetry() async {
        let transport = OrderUITestTransport(arguments: ["--fail-save-once"]), owner = model(transport)
        await owner.load()
        let edit = OrderEditModel(owner: owner)
        await edit.start()
        edit.draft?.internalComment = "Retained draft"
        await edit.review()
        #expect(edit.error != nil && edit.draft?.internalComment == "Retained draft")
        #expect(!edit.requiresReload && !edit.reviewed)
        await edit.review()
        #expect(edit.error == nil && edit.reviewed)
        #expect(await edit.save())
        #expect(owner.detail?.internalComment == "Retained draft")
    }

    @Test func lostMergeResponsePreventsDuplicateMergeAndClosesSafely() async {
        let transport = OrderUITestTransport(arguments: ["--lose-merge-response"]), owner = model(transport)
        await owner.load()
        let edit = OrderEditModel(owner: owner)
        await edit.start(); edit.draft?.internalComment = "Saved once"
        await edit.review()
        #expect(await edit.save() == false)
        #expect(edit.saveUncertain && !edit.canSave)
        #expect(await edit.save() == false)
        #expect(await transport.requests.filter { $0.url.contains("/version/merge/") }.count == 1)
        #expect(await edit.discard())
        #expect(owner.detail?.internalComment == "Saved once")
    }

    @Test func statusAndTrackingFailuresRemainVisibleAndCanRetry() async {
        let transport = OrderUITestTransport(arguments: ["--fail-status-once", "--fail-tracking-once"]), owner = model(transport)
        await owner.load()
        #expect(await owner.transition(entity: "order", entityId: "order-0", actionName: "process", sendMail: false, documentIds: [], internalComment: nil) == false)
        #expect(owner.actionError != nil && owner.detail?.states.first?.stateTechnical == "open")
        #expect(await owner.transition(entity: "order", entityId: "order-0", actionName: "process", sendMail: false, documentIds: [], internalComment: nil))
        #expect(owner.detail?.states.first?.stateTechnical == "in_progress")
        #expect(owner.timeline.first?.fromStateName == "Open" && owner.timeline.first?.userLabel == "Robin Admin")
        #expect(await owner.setTrackingCodes([" TRACK456 ", "TRACK456"]) == false)
        #expect(await owner.setTrackingCodes([" TRACK456 ", "TRACK456"]))
        #expect(owner.detail?.trackingCodes == ["TRACK456"])
        let request = await transport.requests.first { $0.url.hasSuffix("/state/process") }
        #expect(request?.body.flatMap(JSONValue.parse)?["sendMail"] == false)
    }

    @Test func historyFailureIsSeparateFromEmptyHistoryAndRetryWorks() async {
        let owner = model(OrderUITestTransport(arguments: ["--fail-history-once"]))
        await owner.load()
        #expect(owner.detail != nil && owner.error == nil && owner.timelineError != nil)
        await owner.loadTimeline()
        #expect(owner.timelineError == nil && owner.timeline.isEmpty && !owner.timelineLoading)
    }

    @Test func readOnlyPermissionsPreventMutationsAndDraftCreation() async {
        let transport = OrderUITestTransport(arguments: ["--read-only"]), owner = model(transport)
        await owner.load()
        #expect(owner.detail != nil && !owner.canEdit && !owner.canDelete && !owner.canCreateDocuments)
        let edit = OrderEditModel(owner: owner); await edit.start()
        #expect(!edit.ready)
        #expect(await owner.setInternalComment("No") == false)
        #expect(await owner.deleteOrder() == false)
        #expect(await transport.requests.allSatisfy { $0.url.contains("/search/") || $0.url.contains("/state-machine/") || $0.url.contains("/_info/") })
    }

    @Test func partialBulkDeleteRetriesOnlyFailedOrders() async throws {
        let transport = OrderUITestTransport(arguments: ["--fail-delete-once"]), owner = model(transport)
        let listing = try await owner.api.orders.search(orderListCriteria())
        let bulk = OrderBulkModel(api: owner.api, orders: listing.data.map { parseOrder($0, now: 0) })
        await bulk.load(); await bulk.delete()
        #expect(bulk.pending == ["order-1"] && bulk.succeeded == ["order-0", "order-2"])
        await bulk.delete()
        #expect(bulk.pending.isEmpty && bulk.succeeded.count == 3)
        let deletes = await transport.requests.filter { $0.method == .delete }
        #expect(deletes.filter { $0.url.hasSuffix("order-0") }.count == 1)
        #expect(deletes.filter { $0.url.hasSuffix("order-1") }.count == 2)
    }

    @Test func orderCreationReusesCustomerCartAndRequiresExplicitCheckout() async throws {
        let transport = OrderUITestTransport(), owner = model(transport)
        let customer = try #require(try await owner.api.fetchCustomerDetail("customer"))
        let cart = CustomerOrderCreateModel(api: owner.api, customer: customer)
        await cart.start()
        #expect(cart.ready && !cart.canCreate)
        await cart.addProducts(["product"])
        #expect(cart.canCreate)
        #expect(cart.cart?.total == 19)
        #expect(cart.cart?.items.first?.json["price"]?["unitPrice"]?.doubleValue == 19)
        #expect(await transport.requests.allSatisfy { !$0.url.contains("/_proxy-order/") })
        cart.sendMail = false
        #expect(await cart.create() == "created-order")
        let created = try await owner.api.fetchOrderDetail("created-order")
        #expect(created.amountTotal == 19 && created.lineItems.first?.label == "Ceramic mug")
        let request = await transport.requests.first { $0.url.contains("/_proxy-order/") }
        #expect(request?.body.flatMap(JSONValue.parse)?["sendOrderConfirmationMail"] == false)
    }

    @Test func staticDocumentUploadFailureCanResumeWithoutCreatingAnotherDocument() async throws {
        let transport = OrderUITestTransport(arguments: ["--fail-upload-once"]), owner = model(transport)
        _ = try await owner.api.documents.generate(orderId: "order-0", type: "invoice", config: .object(["documentNumber": "UPLOADED"]), staticDocument: true)
        await owner.load()
        let document = try #require(owner.detail?.documents.first { $0.staticDocument })
        #expect(!document.hasFile)
        let data = Data("%PDF-1.4 fixture".utf8)
        #expect(await owner.uploadDocument(document, data: data, fileName: "invoice") == false)
        #expect(owner.actionError != nil)
        #expect(await owner.uploadDocument(document, data: data, fileName: "invoice"))
        #expect(owner.detail?.documents.first(where: { $0.id == document.id })?.hasFile == true)
        let requests = await transport.requests
        #expect(requests.filter { $0.url.contains("/document/invoice/create") }.count == 1)
        #expect(requests.filter { $0.url.contains("/document/" + document.id + "/upload") }.count == 2)
    }

    @Test func sharedCartValidationPreservesWarningsButBlocksUnknownErrors() {
        let warning: JSONValue = .object(["errors": .object(["hint": .object(["message": "Hint", "blockOrder": false])])])
        let failure: JSONValue = .object(["errors": .array([.object(["message": "Invalid order"])])])
        #expect(!CustomerOrderCart(json: warning).blocksCheckout)
        #expect(CustomerOrderCart(json: failure).blocksCheckout)
        #expect(orderCartIssues(warning).first?.id == "hint")
    }

    @Test func moneyPreservesOrderCentsAndCurrencyPrecision() {
        let shop = ConnectedShop(id: "test", name: "Test", baseUrl: "https://order-ui.test", localeCode: "en-US")
        #expect(shop.fmt(103.90, iso: "EUR").contains("103.90"))
        #expect(shop.fmt(103.90, iso: "JPY").contains("104"))
        #expect(shop.fmt(1.234, iso: "KWD").contains("1.234"))
    }

    @Test func listingPagingSearchAndSortUseServerCriteria() async throws {
        let owner = model(OrderUITestTransport(count: 30))
        let state = ListingState<RecentOrder>(source: { try await owner.api.repository("order").search($0) }, baseCriteria: orderListCriteria, mapper: { parseOrder($0, now: 0) })
        state.reload(); await state.fetchTask?.value
        #expect(state.items.count == 25 && state.total == 30)
        state.loadMore(); await state.fetchTask?.value
        #expect(state.items.count == 30 && Set(state.items.map(\.id)).count == 30)
        state.setSorting([ListingSort(field: "orderNumber", ascending: false), ListingSort(field: "id")])
        await state.fetchTask?.value
        #expect(state.items.first?.orderNumber == "100030")
        state.setTerm("Rivera"); state.search(); await state.fetchTask?.value
        #expect(state.items.map(\.id) == ["order-1"])
    }

    @Test func legacyOrderSnapshotsStillDecode() throws {
        let legacy = Data(#"{"id":"old","orderNumber":"1","customer":"Alex","state":"Open","stateTechnical":"open","amount":10,"placedMs":0}"#.utf8)
        let row = try JSONDecoder().decode(RecentOrder.self, from: legacy)
        #expect(row.orderNumber == "1" && row.paymentState == nil && row.salesChannel == nil)
    }
}
