import Foundation

enum PromotionCodeMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, fixed, individual
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .fixed: "Fixed code"
        case .individual: "Individual codes"
        }
    }
}
