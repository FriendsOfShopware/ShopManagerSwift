import SwiftUI

struct PromotionStatusLabel: View {
    let state: PromotionState
    var body: some View {
        Label { Text(state.title) } icon: { Image(systemName: symbol) }.labelStyle(.titleAndIcon).font(.callout).foregroundStyle(tone)
    }
    private var symbol: String {
        switch state {
        case .active: "checkmark.circle.fill"
        case .inactive: "pause.circle"
        case .scheduled: "clock"
        case .expired: "calendar.badge.minus"
        }
    }
    private var tone: Color {
        switch state {
        case .active: Theme.accent
        case .scheduled: .orange
        case .inactive, .expired: .secondary
        }
    }
}
