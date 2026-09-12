import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class OrderEditModel {
    let owner: OrderDetailViewModel
    let versionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    var draft: OrderDetail? { didSet { reviewed = false } }
    private(set) var baseline: OrderDetail?
    private(set) var busy = false
    private(set) var ready = false
    private(set) var reviewed = false
    private(set) var issues: [OrderCartIssue] = []
    private(set) var error: String?
    private(set) var requiresReload = false
    private(set) var saveUncertain = false
    private(set) var knownTags: [CustomerOption] = []
    private var attemptedCreate = false
    private var versionCreated = false
    private var stagedChanges = false
    private var removedItems = Set<String>()

    var api: ShopApi { owner.api }
    var canSave: Bool { ready && !busy && !requiresReload && !saveUncertain && hasChanges && (!reviewed || !issues.contains(where: \.blocksOrder)) }
    var hasChanges: Bool {
        stagedChanges || !removedItems.isEmpty || (draft.flatMap { draft in baseline.map { orderEditPayload(draft: draft, original: $0).objectValue?.isEmpty == false } } ?? false)
    }

    init(owner: OrderDetailViewModel) { self.owner = owner }

    func start() async {
        guard !busy, !ready, owner.permissions.allows("order:update") else { return }
        await perform {
            if self.attemptedCreate {
                do {
                    let existing = try await self.api.fetchOrderDetail(self.owner.orderId, versionId: self.versionId, loadTransitions: false)
                    self.versionCreated = true
                    self.baseline = existing; self.draft = existing; self.ready = true
                    return
                } catch ApiError.notFound { }
            }
            self.attemptedCreate = true
            _ = try await self.api.orders.createVersion(orderId: self.owner.orderId, versionId: self.versionId)
            self.versionCreated = true
            try await self.refresh()
            self.ready = true
        }
        if ready && owner.permissions.allows("tag:read") {
            do { knownTags = try await api.customerOptions("tag", criteria: Criteria().addSorting("name")) }
            catch { self.error = message(error) }
        }
    }

    func review() async {
        guard ready, !busy, !requiresReload, !saveUncertain else { return }
        await perform {
            try self.validate()
            try await self.persist()
            let response = try await self.api.orders.recalculate(orderId: self.owner.orderId, versionId: self.versionId)
            self.issues = orderCartIssues(response)
            try await self.refresh()
            self.reviewed = !self.issues.contains(where: \.blocksOrder)
        }
    }

    /// First click calculates a review; the second explicitly commits the reviewed version.
    func save() async -> Bool {
        guard canSave else { return false }
        guard reviewed else { await review(); return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await api.orders.mergeVersion(versionId)
            versionCreated = false; stagedChanges = false; ready = false
            await owner.load()
            return true
        } catch {
            saveUncertain = uncertain(error)
            self.error = saveUncertain ? String(localized: "The save response was lost. Refresh the order to check whether your changes were saved before editing again.") : message(error)
            return false
        }
    }

    func discard() async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            if attemptedCreate {
                do { try await api.orders.discardVersion(orderId: owner.orderId, versionId: versionId) }
                catch ApiError.notFound { }
            }
            versionCreated = false; ready = false
            if saveUncertain { await owner.load() }
            return true
        } catch { self.error = message(error); return false }
    }

    func reloadDraft() async {
        guard !busy, !saveUncertain else { return }
        await perform {
            try await self.refresh()
            self.removedItems = []
            self.requiresReload = false
            self.stagedChanges = true
            self.issues = []
        }
    }

    func setQuantity(id: String, quantity: Int) {
        guard owner.permissions.allows("order_line_item:update"), var order = draft, let index = order.lineItems.firstIndex(where: { $0.id == id }), quantity > 0 else { return }
        let previous = order.lineItems[index].quantity
        var visited = Set<String>()
        func update(_ parentID: String, old: Int, new: Int) {
            guard visited.insert(parentID).inserted else { return }
            for childIndex in order.lineItems.indices where order.lineItems[childIndex].parentId == parentID {
                let child = order.lineItems[childIndex]
                let changed = max(1, child.quantity / max(1, old)) * new
                order.lineItems[childIndex].quantity = changed
                update(child.id, old: child.quantity, new: changed)
            }
        }
        order.lineItems[index].quantity = quantity
        update(id, old: previous, new: quantity)
        draft = order
    }

    func removeItem(_ id: String) {
        guard owner.permissions.allows("order_line_item:delete"), var order = draft else { return }
        var ids: Set<String> = [id]
        var changed = true
        while changed {
            let previous = ids.count
            for item in order.lineItems where item.parentId.map(ids.contains) == true { ids.insert(item.id) }
            changed = ids.count != previous
        }
        order.lineItems.removeAll { ids.contains($0.id) }
        removedItems.formUnion(ids)
        draft = order
    }

    func updateAddress(_ address: EditableAddress) {
        guard owner.permissions.allows("order_address:update"), var order = draft else { return }
        if order.billing?.id == address.id { order.billing = address }
        for index in order.deliveries.indices where order.deliveries[index].address?.id == address.id { order.deliveries[index].address = address }
        draft = order
    }

    func addProducts(_ ids: Set<String>) async {
        guard owner.permissions.allows("order_line_item:create"), owner.permissions.allows("product:read") else { return }
        await mutateDraft {
            for id in ids.sorted() { try await self.api.orders.addProduct(orderId: self.owner.orderId, versionId: self.versionId, productId: id, quantity: 1) }
            return try await self.api.orders.recalculate(orderId: self.owner.orderId, versionId: self.versionId)
        }
    }

    func addItem(_ item: JSONValue, credit: Bool) async -> Bool {
        guard owner.permissions.allows("order_line_item:create"), !credit || owner.permissions.allows("order:create:discount") else { return false }
        await mutateDraft {
            try await self.api.orders.addLineItem(orderId: self.owner.orderId, versionId: self.versionId, item: item, credit: credit)
            return try await self.api.orders.recalculate(orderId: self.owner.orderId, versionId: self.versionId)
        }
        return error == nil && !issues.contains(where: \.blocksOrder)
    }

    func addPromotion(_ code: String) async {
        guard owner.permissions.allows("order_line_item:create"), owner.permissions.allows("order:create:discount") else { return }
        await mutateDraft { try await self.api.orders.addPromotion(orderId: self.owner.orderId, versionId: self.versionId, code: code.trimmed) }
    }

    func applyAutomaticPromotions() async {
        guard owner.permissions.allows("order_line_item:create"), owner.permissions.allows("order:create:discount") else { return }
        await mutateDraft { try await self.api.orders.applyAutomaticPromotions(orderId: self.owner.orderId, versionId: self.versionId) }
    }

    private func mutateDraft(_ action: () async throws -> JSONValue) async {
        guard ready, !busy, !requiresReload, !saveUncertain else { return }
        await perform {
            try await self.persist()
            self.stagedChanges = true
            do {
                let response = try await action()
                self.issues = orderCartIssues(response)
                try await self.refresh()
            } catch {
                // A batch may have partially applied, even when the last response is a validation error.
                self.requiresReload = true
                throw error
            }
        }
    }

    private func persist() async throws {
        guard let draft, let baseline else { return }
        let payload = orderEditPayload(draft: draft, original: baseline)
        let removedTags = Set(baseline.tags.map(\.id)).subtracting(draft.tags.map(\.id)).sorted()
        if payload.objectValue?.isEmpty == false || !removedTags.isEmpty {
            try await api.orders.save(orderId: owner.orderId, payload: payload, versionId: versionId, removedTagIds: removedTags)
            stagedChanges = true
        }
        for id in removedItems.sorted() {
            do { try await api.orders.removeLineItem(id, versionId: versionId) }
            catch ApiError.notFound { }
            removedItems.remove(id)
            stagedChanges = true
        }
    }

    private func refresh() async throws {
        let result = try await api.fetchOrderDetail(owner.orderId, versionId: versionId, loadTransitions: false)
        baseline = result; draft = result
    }

    private func validate() throws {
        guard let draft, !draft.lineItems.isEmpty else { throw invalid("An order must contain at least one item.") }
        guard draft.customerEmail.contains("@"), !draft.customerEmail.trimmed.contains(" ") else { throw invalid("Enter a valid email address.") }
        for item in draft.lineItems {
            guard !item.label.trimmed.isEmpty, item.quantity > 0, item.unitPrice.isFinite else { throw invalid("Check the item names, quantities, and prices.") }
            if item.type == "credit" && item.unitPrice > 0 { throw invalid("A credit must have a negative amount.") }
            if item.type == "product" || item.type == "custom", item.unitPrice < 0 { throw invalid("Item prices cannot be negative. Add a credit instead.") }
        }
        for field in owner.customFieldSets.flatMap(\.fields) {
            if let error = field.validationError(draft.customFields[field.name]) { throw ApiError.unexpected(status: 400, message: error) }
        }
        guard draft.deliveries.allSatisfy({ ($0.shippingCosts["totalPrice"]?.doubleValue ?? 0).isFinite }) else {
            throw invalid("Enter a valid shipping cost.")
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await action() }
        catch {
            self.error = message(error)
            if versionCreated && uncertain(error) { requiresReload = true }
        }
    }
    private func invalid(_ key: String.LocalizationValue) -> ApiError { .unexpected(status: 400, message: String(localized: key)) }
    private func message(_ error: Error) -> String { (error as? ApiError)?.message ?? error.localizedDescription }
    private func uncertain(_ error: Error) -> Bool {
        switch error {
        case ApiError.network, ApiError.server: true
        case ApiError.unexpected(let status, _): status >= 500 || status < 400
        default: false
        }
    }
}
