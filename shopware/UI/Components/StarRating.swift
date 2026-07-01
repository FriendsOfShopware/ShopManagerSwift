import SwiftUI

/// Five-star rating display (filled up to `points`). A shared, self-contained component —
/// used by the review inbox and anywhere a compact rating is shown.
struct StarRating: View {
    let points: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 5, id: \.self) { i in
                Image(systemName: i < points ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(i < points ? Theme.accent : Color.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("^[\(points) star](inflect: true)")
    }
}
