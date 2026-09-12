import SwiftUI
import ShopwareAdminAPI

struct ReviewRating: View {
    let points: Double
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").foregroundStyle(.tint)
            Text(points, format: .number.precision(.fractionLength(0...2))).monospacedDigit()
            Text("/ 5").foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore)
        .accessibilityLabel("\(points.formatted(.number.precision(.fractionLength(0...2)))) out of 5 stars")
    }
}
