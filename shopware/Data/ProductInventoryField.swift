import Foundation

enum ProductInventoryField: String, CaseIterable, Identifiable {
    case stock, minPurchase, purchaseSteps, maxPurchase, restockTime
    case weight, width, height, length, purchaseUnit, referenceUnit
    var id: String { rawValue }
    var isInteger: Bool { [.stock, .minPurchase, .purchaseSteps, .maxPurchase, .restockTime].contains(self) }
    var isRequired: Bool { [.stock, .minPurchase, .purchaseSteps].contains(self) }
    var minimum: Int { self == .stock ? Int(Int32.min) : [.minPurchase, .purchaseSteps].contains(self) ? 1 : 0 }
    var title: LocalizedStringResource {
        switch self {
        case .stock: "Stock"
        case .minPurchase: "Minimum purchase"
        case .purchaseSteps: "Purchase steps"
        case .maxPurchase: "Maximum purchase"
        case .restockTime: "Restock time (days)"
        case .weight: "Weight (kg)"
        case .width: "Width (mm)"
        case .height: "Height (mm)"
        case .length: "Length (mm)"
        case .purchaseUnit: "Purchase unit"
        case .referenceUnit: "Reference unit"
        }
    }
}
