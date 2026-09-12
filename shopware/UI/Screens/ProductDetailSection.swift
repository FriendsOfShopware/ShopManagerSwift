import Foundation

enum ProductDetailSection: String, CaseIterable, Identifiable {
    case overview, prices, inventory, media, variants
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self { case .overview: "Overview"; case .prices: "Pricing"; case .inventory: "Inventory"; case .media: "Media"; case .variants: "Variants" }
    }
}
