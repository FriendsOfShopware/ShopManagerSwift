import Foundation
import Observation
import ShopwareAdminAPI

@MainActor
@Observable
final class OrderDetailViewModel {
    let api: ShopApi
    let shop: ConnectedShop
    let orderId: String

    private(set) var detail: OrderDetail?
    private(set) var permissions = AdminPermissions()
    private(set) var timeline: [OrderTimelineEntry] = []
    private(set) var customFieldSets: [CustomerCustomFieldSet] = []
    private(set) var loading = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var permissionsError: String?
    private(set) var timelineError: String?
    private(set) var timelineLoading = false
    private(set) var customFieldsError: String?
    var actionError: String?
    @ObservationIgnored private var requestID = 0

    var busyMessage: String? { busy ? String(localized: "Working…") : nil }
    var canEdit: Bool { permissions.allows("order:update") && !busy }
    var canDelete: Bool { permissions.allows("order:delete") && !busy }
    var canCreateDocuments: Bool { permissions.allows("document:create") && !busy }
    func canTransition(_ state: OrderStateInfo) -> Bool {
        canEdit && permissions.allows(state.entity + ":update") && permissions.allows("state_machine_history:create")
    }

    init(repo: AppRepository, shop: ConnectedShop, orderId: String) {
        api = repo.apiFor(shop)
        self.shop = shop
        self.orderId = orderId
    }

    func load() async {
        requestID += 1
        let id = requestID
        loading = true
        error = nil
        defer { if id == requestID { loading = false } }
        do {
            let result = try await api.permissions()
            guard id == requestID else { return }
            permissions = result
            permissionsError = nil
        } catch {
            guard id == requestID else { return }
            permissions = AdminPermissions()
            permissionsError = message(error)
        }
        do {
            let result = try await api.fetchOrderDetail(orderId, loadTransitions: permissions.allows("order:update"))
            guard id == requestID else { return }
            detail = result
            await loadTimeline()
            guard id == requestID else { return }
            await loadCustomFields()
        } catch is CancellationError { }
        catch { if id == requestID { self.error = message(error) } }
    }

    func loadTimeline() async {
        guard let detail else { return }
        let id = requestID
        timelineError = nil
        guard permissions.allows("state_machine_history:read") else { timeline = []; return }
        timelineLoading = true
        defer { if id == requestID { timelineLoading = false } }
        do {
            let rows = try await api.fetchOrderTimeline(referencedIds: detail.states.map(\.entityId))
            if id == requestID { timeline = rows }
        } catch {
            if id == requestID { timelineError = message(error) }
        }
    }

    func loadCustomFields() async {
        let id = requestID
        customFieldsError = nil
        guard permissions.allows("custom_field_set:read") else { customFieldSets = []; return }
        do {
            let fields = try await api.customerCustomFieldSets(entity: "order", locale: shop.localeCode ?? Locale.current.identifier)
            if id == requestID { customFieldSets = fields }
        } catch {
            if id == requestID { customFieldsError = message(error) }
        }
    }

    @discardableResult
    func transition(entity: String, entityId: String, actionName: String,
                    sendMail: Bool, documentIds: [String], internalComment: String?) async -> Bool {
        guard canEdit, permissions.allows(entity + ":update"), permissions.allows("state_machine_history:create") else { return false }
        return await run {
            try await self.api.stateMachine.transitionWithOptions(entity: entity, entityId: entityId, actionName: actionName,
                                                                  sendMail: sendMail, documentIds: documentIds, internalComment: internalComment)
        }
    }

    @discardableResult
    func generateDocument(type: String) async -> Bool {
        guard canCreateDocuments else { return false }
        return await run { try await self.api.documents.create(orderId: self.orderId, type: type) }
    }

    func downloadDocument(_ document: OrderDocument) async -> Data? {
        guard !busy else { return nil }
        busy = true
        actionError = nil
        defer { busy = false }
        do { return try await api.documents.download(documentId: document.id, deepLinkCode: document.deepLinkCode) }
        catch { actionError = message(error); return nil }
    }

    @discardableResult
    func uploadDocument(_ document: OrderDocument, data: Data, fileName: String) async -> Bool {
        guard permissions.allows("document:update"), !document.hasFile else { return false }
        return await run { try await self.api.documents.upload(documentId: document.id, data: data, fileName: fileName) }
    }

    @discardableResult
    func setTrackingCodes(_ codes: [String], deliveryId: String? = nil) async -> Bool {
        guard canEdit, permissions.allows("order_delivery:update"), let id = deliveryId ?? detail?.deliveryId else { return false }
        var seen = Set<String>()
        let codes = codes.map(\.trimmed).filter { !$0.isEmpty && seen.insert($0).inserted }
        return await run {
            try await self.api.repository("order-delivery").patch(id, .object(["trackingCodes": .array(codes.map { .string($0) })]))
        }
    }

    @discardableResult
    func setInternalComment(_ comment: String?) async -> Bool {
        guard canEdit else { return false }
        return await run {
            try await self.api.repository("order").patch(self.orderId, .object(["internalComment": nullableField(comment)]))
        }
    }

    func deleteOrder() async -> Bool {
        guard canDelete else { return false }
        return await run(reload: false) { try await self.api.repository("order").delete(self.orderId) }
    }

    private func run(reload: Bool = true, _ work: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        actionError = nil
        defer { busy = false }
        do {
            try await work()
            if reload { await load() }
            return true
        } catch { actionError = message(error); return false }
    }

    private func message(_ error: Error) -> String {
        (error as? ApiError)?.message ?? error.localizedDescription
    }
}
