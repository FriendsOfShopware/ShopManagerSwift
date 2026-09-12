import SwiftUI
import ShopwareAdminAPI

struct PromotionConditionsEditorSheet: View {
    @State private var original: PromotionItem
    @State private var draft: PromotionConditionsDraft
    @State private var selecting: PromotionConditionSelection?
    let actions: PromotionActions
    let onSave: () -> Void
    init(promotion: PromotionItem, actions: PromotionActions, onSave: @escaping () -> Void) {
        _original = State(initialValue: promotion)
        _draft = State(initialValue: PromotionConditionsDraft(promotion))
        self.actions = actions; self.onSave = onSave
    }
    var body: some View {
        PromotionFormSheet(title: "Edit conditions", busy: actions.busy, changed: draft != PromotionConditionsDraft(original),
                           canSave: actions.canEditConditions && draft != PromotionConditionsDraft(original), error: actions.error) {
            let saved = await actions.saveConditions(original: original, draft: draft)
            if saved { onSave() }; return saved
        } content: {
            Section {
                choice(.channels, selection: $draft.salesChannels)
            } footer: { Text("The promotion is available only in its assigned sales channels.") }
            Section("Combination") {
                Toggle("Prevent combination with other promotions", isOn: $draft.preventCombination)
                choice(.exclusions, selection: $draft.exclusions).disabled(draft.preventCombination)
            }
            Section("Rules") {
                if !original.customerRestriction { choice(.customer, selection: $draft.personaRules) }
                choice(.cart, selection: $draft.cartRules)
                choice(.order, selection: $draft.orderRules)
            }
            if original.useSetGroups || original.customerRestriction {
                Section { Text("Existing product groups and selected customers continue to apply.").foregroundStyle(.secondary) }
            }
        }
        .sheet(item: $selecting) { kind in
            CustomerEntitySelectionSheet(api: actions.api, entity: kind.entity, title: String(localized: kind.title), multiple: true,
                                         selected: binding(kind).wrappedValue, sortField: "name", criteria: {
                let criteria = Criteria().addSorting("name")
                if kind.isRule { criteria.addAssociation("conditions") }
                if kind == .exclusions { criteria.addFilter(Criteria.not("AND", Criteria.equals("id", .string(original.id)))) }
                return criteria
            }, isEnabled: { entity in !kind.isRule || PromotionRuleCompatibility.allows(entity, customer: kind == .customer) }, unavailableMessage: kind.isRule ? String(localized: "Only compatible rules can be selected.") : nil) {
                binding(kind).wrappedValue = $0
            }
        }
        .onAppear { actions.error = nil }
    }
    private func choice(_ kind: PromotionConditionSelection, selection: Binding<Set<String>>) -> some View {
        Button { selecting = kind } label: {
            LabeledContent { Text("\(selection.wrappedValue.count) selected").foregroundStyle(.secondary) } label: { Text(kind.title) }
        }.accessibilityIdentifier("promotion.conditions.\(kind.rawValue)")
    }
    private func binding(_ kind: PromotionConditionSelection) -> Binding<Set<String>> {
        switch kind { case .channels: $draft.salesChannels; case .exclusions: $draft.exclusions; case .customer: $draft.personaRules; case .cart: $draft.cartRules; case .order: $draft.orderRules }
    }
}
private enum PromotionConditionSelection: String, Identifiable {
    case channels, exclusions, customer, cart, order
    var id: String { rawValue }
    var isRule: Bool { self == .customer || self == .cart || self == .order }
    var entity: String { isRule ? "rule" : self == .channels ? "sales-channel" : "promotion" }
    var title: LocalizedStringResource {
        switch self { case .channels: "Sales channels"; case .exclusions: "Excluded promotions"; case .customer: "Customer rules"; case .cart: "Cart rules"; case .order: "Order rules" }
    }
}
