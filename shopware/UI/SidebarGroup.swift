import SwiftUI

enum SidebarGroup: String, CaseIterable, Identifiable {
    case overview, catalog
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .catalog: "Catalog"
        }
    }

    var destinations: [Destination] {
        switch self {
        case .overview: [.home, .orders, .customers, .reports]
        case .catalog: [.products, .promotions, .media, .reviews]
        }
    }
}
