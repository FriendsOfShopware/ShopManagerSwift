import SwiftUI
import ShopwareAdminAPI

struct ReviewStatus: View {
    let approved: Bool
    var body: some View {
        Label(approved ? "Approved" : "Pending", systemImage: approved ? "checkmark.circle" : "clock")
            .labelStyle(.titleAndIcon)
            .font(.caption).foregroundStyle(approved ? Theme.accent : .secondary)
            .accessibilityElement(children: .ignore).accessibilityLabel(approved ? "Approved" : "Pending")
            .accessibilityIdentifier("review.status")
    }
}
