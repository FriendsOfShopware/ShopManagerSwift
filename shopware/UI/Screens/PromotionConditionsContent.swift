import SwiftUI
import ShopwareAdminAPI

struct PromotionConditionsContent: View {
    let promotion: PromotionItem
    let vm: PromotionDetailViewModel
    let edit: () -> Void
    var body: some View {
        Form {
            Section {
                Button("Edit conditions…", systemImage: "pencil", action: edit).disabled(!vm.actions.canEditConditions).accessibilityIdentifier("promotion.conditions.edit")
            }
            Section("Sales channels") {
                references(promotion.salesChannels, empty: "No sales channels assigned")
            }
            Section("Combination") {
                LabeledContent("Combine with other promotions", value: promotion.preventCombination ? String(localized: "Not allowed") : String(localized: "Allowed"))
                if let error = vm.exclusionsError { PromotionNotice(message: error) { Task { await vm.loadExclusions() } } }
                if !vm.exclusions.isEmpty {
                    LabeledContent("Excluded promotions", value: vm.exclusions.map(\.name).formatted())
                }
            }
            if !promotion.customerRestriction {
                Section { references(promotion.personaRules, empty: "All customers") }
                header: { Text("Customer rules") } footer: { Text("At least one selected rule must match within each group.") }
            }
            Section("Cart rules") { references(promotion.cartRules, empty: "No cart rules") }
            Section("Order rules") { references(promotion.orderRules, empty: "No order rules") }
            if promotion.customerRestriction || !promotion.customers.isEmpty {
                Section("Selected customers") { references(promotion.customers, empty: "No customers assigned") }
            }
            if promotion.useSetGroups {
                Section("Product groups") {
                    Text("This promotion uses product groups to determine eligible items.").foregroundStyle(.secondary)
                    ForEach(promotion.setGroups) { group in
                        LabeledContent(group.title, value: group.value)
                        ForEach(group.rules) { Text($0.name).foregroundStyle(.secondary) }
                    }
                }
            }
        }.groupedFormStyle()
    }
    @ViewBuilder private func references(_ values: [PromotionReference], empty: LocalizedStringKey) -> some View {
        if values.isEmpty { Text(empty).foregroundStyle(.secondary) }
        ForEach(values) { Text($0.name).textSelection(.enabled) }
    }
}
