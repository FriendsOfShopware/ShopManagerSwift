import SwiftUI
import ShopwareAdminAPI

struct ProductInventoryContent: View {
    let product: ProductItem
    let actions: ProductActions
    let edit: () -> Void
    var body: some View {
        Form {
            Section {
                Button("Edit inventory…", systemImage: "pencil", action: edit).disabled(!actions.canEdit).accessibilityIdentifier("product.inventory.edit")
            }
            Section("Stock") {
                LabeledContent("Stock") { Text(product.stock, format: .number) }
                LabeledContent("Available stock") { if let value = product.availableStock { Text(value, format: .number) } else { Text("—") } }
                LabeledContent("Clearance sale", value: product.entity.boolean("isCloseout") == true ? String(localized: "Yes") : String(localized: "No"))
            }
            Section("Delivery") {
                LabeledContent("Delivery time", value: product.entity.entity("deliveryTime")?.translated("name") ?? "—")
                number(.restockTime)
                LabeledContent("Free shipping", value: product.entity.boolean("shippingFree") == true ? String(localized: "Yes") : String(localized: "No"))
                LabeledContent("Release date") { if let date = product.entity.date("releaseDate") { Text(date, format: .dateTime.day().month().year()) } else { Text("—") } }
            }
            Section("Purchase limits") { number(.minPurchase); number(.purchaseSteps); number(.maxPurchase) }
            Section("Measurements") { number(.weight); number(.width); number(.height); number(.length) }
            Section("Packaging") {
                LabeledContent("Unit", value: product.entity.entity("unit")?.translated("name") ?? "—")
                number(.purchaseUnit); number(.referenceUnit)
                LabeledContent("Pack unit", value: product.entity.translated("packUnit") ?? "—")
                LabeledContent("Pack unit (plural)", value: product.entity.translated("packUnitPlural") ?? "—")
            }
        }.groupedFormStyle().accessibilityIdentifier("product.inventory")
    }
    private func number(_ field: ProductInventoryField) -> some View {
        LabeledContent {
            if let value = product.entity.double(field.rawValue) { Text(value, format: .number) } else { Text("—") }
        } label: { Text(field.title) }
    }
}
