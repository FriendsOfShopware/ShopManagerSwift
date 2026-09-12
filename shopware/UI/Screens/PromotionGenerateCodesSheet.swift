import SwiftUI

struct PromotionGenerateCodesSheet: View {
    let promotion: PromotionItem
    @Bindable var actions: PromotionActions
    let onGenerate: () -> Void
    @State private var amount = "10"
    private var count: Int? { Int(amount.trimmed).flatMap { (1...500).contains($0) ? $0 : nil } }
    var body: some View {
        PromotionFormSheet(title: "Generate codes", busy: actions.busy, changed: amount != "10", canSave: count != nil && actions.canGenerate,
                           error: actions.error, saveTitle: "Generate", idealHeight: 320) {
            guard let count else { return false }
            let success = await actions.generate(promotion: promotion, amount: count)
            if success { onGenerate() }
            return success
        } content: {
            Section {
                LabeledContent("Number of codes") {
                    TextField("Amount", text: $amount).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.codes.amount")
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                LabeledContent("Code pattern", value: promotion.codePattern)
                if count == nil { Text("Enter a whole number between 1 and 500.").foregroundStyle(.red) }
            } header: { Text(promotion.name) } footer: { Text("New codes are added to the existing codes. Each code can be redeemed once.") }
        }.onAppear { actions.error = nil }
    }
}
