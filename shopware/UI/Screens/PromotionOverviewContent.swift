import SwiftUI

struct PromotionOverviewContent: View {
    let promotion: PromotionItem
    let vm: PromotionDetailViewModel
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    PromotionStatusLabel(state: promotion.state()).accessibilityIdentifier("promotion.status")
                    Text(promotion.name).font(.title2.bold()).textSelection(.enabled).accessibilityIdentifier("promotion.name")
                    PromotionDiscountText(discounts: promotion.discounts, currency: vm.actions.currencyCode).foregroundStyle(.secondary)
                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Schedule") {
                LabeledContent("Starts") { if let date = promotion.validFrom { Text(date, format: .dateTime.day().month().year().hour().minute()) } else { Text("No start date") } }
                LabeledContent("Ends") { if let date = promotion.validUntil { Text(date, format: .dateTime.day().month().year().hour().minute()) } else { Text("No end date") } }
                LabeledContent("Priority") { Text(promotion.priority, format: .number) }
            }
            Section("Redemptions") {
                LabeledContent("Redeemed") { Text(promotion.orderCount, format: .number) }
                LabeledContent("Total limit") { if let count = promotion.maxRedemptionsGlobal { Text(count, format: .number) } else { Text("Unlimited") } }
                LabeledContent("Per customer") { if let count = promotion.maxRedemptionsPerCustomer { Text(count, format: .number) } else { Text("Unlimited") } }
                if promotion.orderCount > 0 { Text("Redeemed promotions cannot be deleted or have their discounts changed.").font(.callout).foregroundStyle(.secondary) }
            }
            Section("Promotion codes") {
                LabeledContent("Code type") { Text(promotion.codeMode.title) }
                if promotion.codeMode == .fixed { Text(promotion.code).monospaced().textSelection(.enabled).accessibilityIdentifier("promotion.fixedCode") }
                if promotion.codeMode == .automatic { Text("Applied automatically when the promotion's conditions are met.").foregroundStyle(.secondary) }
            }
            Section("Sales channels") {
                if promotion.salesChannels.isEmpty { Text("No sales channels assigned").foregroundStyle(.secondary) }
                ForEach(promotion.salesChannels) { Text($0.name) }
            }
            if let error = vm.fieldsError { Section { PromotionNotice(message: error) { Task { await vm.loadFields() } } } }
            ForEach(vm.fields) { set in
                Section(set.label) {
                    ForEach(set.fields) { CustomerCustomFieldSummaryRow(field: $0, value: promotion.customFields[$0.name], api: vm.actions.api) }
                }
            }
        }.groupedFormStyle()
    }
}
