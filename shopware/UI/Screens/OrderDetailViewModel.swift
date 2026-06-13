import Foundation
import Observation
import ShopwareAdminAPI

@MainActor
@Observable
final class OrderDetailViewModel {
    private let repo: AppRepository
    let shop: ConnectedShop
    let orderId: String

    private(set) var detail: OrderDetail?
    private(set) var timeline: [OrderTimelineEntry] = []
    private(set) var loading = false
    private(set) var error: String?
    var busyMessage: String?

    init(repo: AppRepository, shop: ConnectedShop, orderId: String) {
        self.repo = repo
        self.shop = shop
        self.orderId = orderId
    }

    func load() async {
        loading = true
        error = nil
        do {
            let d = try await repo.orderDetail(shop, orderId: orderId)
            detail = d
            await loadTimeline(for: d)
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func loadTimeline(for detail: OrderDetail) async {
        let referencedIds = detail.states.map(\.entityId)
        // A history fetch failure degrades to an empty list (the card just hides).
        timeline = (try? await repo.orderTimeline(shop, referencedIds: referencedIds)) ?? []
    }

    /// Generic transition (no mail options).
    func transition(url: String) async {
        await run { try await repo.transition(shop, transitionUrl: url) }
    }

    /// Entity-specific transition carrying confirmation-mail options.
    func transition(
        entity: String, entityId: String, actionName: String,
        sendMail: Bool, documentIds: [String], internalComment: String?
    ) async {
        await run {
            try await repo.transitionOrderState(
                shop, entity: entity, entityId: entityId, actionName: actionName,
                sendMail: sendMail, documentIds: documentIds, internalComment: internalComment
            )
        }
    }

    func generateDocument(type: String) async {
        await run { try await repo.generateDocument(shop, orderId: orderId, type: type) }
    }

    func downloadDocument(_ doc: OrderDocument) async -> Data? {
        try? await repo.downloadDocument(shop, documentId: doc.id, deepLinkCode: doc.deepLinkCode)
    }

    func setTrackingCodes(_ codes: [String]) async {
        guard let deliveryId = detail?.deliveryId else { return }
        await run { try await repo.setTrackingCodes(shop, deliveryId: deliveryId, codes: codes) }
    }

    func setInternalComment(_ comment: String?) async {
        await run { try await repo.setInternalComment(shop, orderId: orderId, comment: comment) }
    }

    /// Runs a mutation, shows a busy state, then reloads the detail + timeline.
    private func run(_ work: () async throws -> Void) async {
        busyMessage = "Working…"
        defer { busyMessage = nil }
        do {
            try await work()
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }
}
