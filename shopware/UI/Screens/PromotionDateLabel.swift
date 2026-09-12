import SwiftUI

struct PromotionDateLabel: View {
    let date: Date?
    var body: some View {
        if let date { Text(date, format: .dateTime.day().month().year()).lineLimit(1) }
        else { Text("—").foregroundStyle(.secondary) }
    }
}
