import Foundation

enum PromotionState: String, Sendable {
    case active, inactive, scheduled, expired
    var title: LocalizedStringResource {
        switch self {
        case .active: "Active"
        case .inactive: "Inactive"
        case .scheduled: "Scheduled"
        case .expired: "Expired"
        }
    }
}
