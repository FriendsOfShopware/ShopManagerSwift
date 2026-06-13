import Foundation
import ShopwareAdminAPI

extension ShopApi {
    /// Approves or rejects a product review by patching its `status` flag.
    func setReviewStatus(reviewId: String, approved: Bool) async throws {
        try await repository("product-review").patch(reviewId, .object(["status": .bool(approved)]))
    }
}
