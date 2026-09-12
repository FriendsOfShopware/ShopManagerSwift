import SwiftUI
import ShopwareAdminAPI

struct ReviewListRow: View {
    let review: ReviewItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewSummaryLine(review: review)
            Text(review.title).font(.headline).lineLimit(2)
            Text(review.productName).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            ViewThatFits(in: .horizontal) {
                HStack { Text(review.reviewer); Text("·"); ReviewDate(date: review.createdAt); if review.hasReply { Label("Replied", systemImage: "text.bubble") } }
                VStack(alignment: .leading) { Text(review.reviewer); ReviewDate(date: review.createdAt); if review.hasReply { Label("Replied", systemImage: "text.bubble") } }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}
