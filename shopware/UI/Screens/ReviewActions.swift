import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class ReviewActions {
    let api: ShopApi
    private(set) var permissions = AdminPermissions()
    private(set) var permissionsError: String?
    private(set) var busy = false
    var error: String?
    init(api: ShopApi) { self.api = api }
    var canEdit: Bool { permissions.allows("product_review:update") && !busy }
    var canDelete: Bool { permissions.allows("product_review:delete") && !busy }

    func loadPermissions() async {
        do { permissions = try await api.permissions(); permissionsError = nil }
        catch { permissions = AdminPermissions(); permissionsError = error.localizedDescription }
    }

    func save(id: String, draft: ReviewDraft, sets: [CustomerCustomFieldSet]) async -> Bool {
        guard canEdit else { return false }
        if let validation = draft.validationError(sets: sets) { error = validation; return false }
        return await run { try await self.api.repository("product-review").patch(id, draft.payload) }
    }

    func approve(id: String, approved: Bool) async -> Bool {
        guard canEdit else { return false }
        return await run { try await self.api.setReviewStatus(reviewId: id, approved: approved) }
    }

    /// Successful deletions are removed immediately; only failed IDs remain selected for retry.
    func delete(ids: Set<String>) async -> Set<String> {
        guard canDelete, !ids.isEmpty else { return [] }
        busy = true; error = nil
        defer { busy = false }
        var succeeded = Set<String>()
        var failures: [String] = []
        for id in ids.sorted() {
            do { try await api.repository("product-review").delete(id); succeeded.insert(id) }
            catch ApiError.notFound { succeeded.insert(id) }
            catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { error = String(localized: "\(failures.count) reviews couldn't be deleted. Try again to delete the remaining reviews.") + "\n" + failures[0] }
        return succeeded
    }

    private func run(_ operation: () async throws -> Void) async -> Bool {
        busy = true; error = nil
        defer { busy = false }
        do { try await operation(); return true }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription; return false }
    }
}
