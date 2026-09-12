import SwiftUI
import ShopwareAdminAPI

struct ReviewSummaryLine: View {
    let review: ReviewItem
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                ReviewRating(points: review.points).fixedSize()
                Spacer()
                ReviewStatus(approved: review.approved).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                ReviewRating(points: review.points)
                ReviewStatus(approved: review.approved)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
