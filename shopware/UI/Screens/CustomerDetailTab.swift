import SwiftUI

enum CustomerDetailTab: String, CaseIterable, Identifiable {
    case general, addresses, orders
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .addresses: "Addresses"
        case .orders: "Orders"
        }
    }
}
