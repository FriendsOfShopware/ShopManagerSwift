import SwiftUI
import ShopwareAdminAPI

struct PromotionDetailWorkspace: View {
    let vm: PromotionDetailViewModel
    let promotion: PromotionItem
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tab = PromotionSection.overview
    @State private var sheet: PromotionDetailSheet?
    @State private var deleting = false
    @State private var discountToDelete: PromotionDiscount?
    @State private var codesRevision = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Group {
                    if typeSize.isAccessibilitySize { sections.pickerStyle(.menu) }
                    else { sections.pickerStyle(.segmented).labelsHidden() }
                }.frame(maxWidth: 520)
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).padding(.vertical, 12).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = vm.error { PromotionNotice(message: error) { Task { await vm.load() } } }
            if let error = vm.actions.permissionsError { PromotionNotice(message: error) { Task { await vm.actions.loadPermissions() } } }
            if let error = vm.actions.currencyError { PromotionNotice(message: error) { Task { await vm.actions.loadCurrency() } } }
            Group {
                switch tab {
                case .overview: PromotionOverviewContent(promotion: promotion, vm: vm)
                case .discounts: PromotionDiscountsContent(promotion: promotion, actions: vm.actions, edit: { sheet = .discount($0) }, delete: { discountToDelete = $0 })
                case .conditions: PromotionConditionsContent(promotion: promotion, vm: vm) { sheet = .conditions }
                case .codes: PromotionCodesView(promotion: promotion, actions: vm.actions, revision: codesRevision) { sheet = .generate }
                }
            }.frame(maxWidth: tab == .codes ? .infinity : 920)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay { if vm.loading { ProgressView("Loading promotion…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit promotion", systemImage: "pencil") { sheet = .settings }
                    .disabled(!vm.actions.canEdit || vm.loading || vm.fieldsError != nil).accessibilityIdentifier("promotion.edit")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if vm.actions.permissions.allows("promotion:update") {
                        Button(promotion.active ? "Deactivate" : "Activate", systemImage: promotion.active ? "pause.circle" : "play.circle") {
                            Task { if await vm.actions.setActive(id: promotion.id, active: !promotion.active) { saved() } }
                        }.accessibilityIdentifier("promotion.toggleActive")
                    }
                    Button("Refresh promotion", systemImage: "arrow.clockwise") { Task { await vm.load(); codesRevision += 1 } }
                    if vm.actions.permissions.allows("promotion:delete") {
                        Button("Delete promotion…", systemImage: "trash", role: .destructive) { deleting = true }
                            .disabled(promotion.orderCount > 0).accessibilityIdentifier("promotion.delete")
                    }
                } label: { Label("Promotion actions", systemImage: "ellipsis.circle") }
                .disabled(vm.actions.busy || vm.loading).accessibilityIdentifier("promotion.actions")
            }
        }
        .sheet(item: $sheet, onDismiss: { vm.actions.error = nil }) { destination in
            switch destination {
            case .settings: PromotionEditorSheet(promotion: promotion, fields: vm.fields, actions: vm.actions) { _ in saved() }
            case .conditions: PromotionConditionsEditorSheet(promotion: promotion, actions: vm.actions, onSave: saved)
            case .discount(let discount): PromotionDiscountEditorSheet(promotion: promotion, discount: discount, actions: vm.actions, onSave: saved)
            case .generate: PromotionGenerateCodesSheet(promotion: promotion, actions: vm.actions) { codesRevision += 1 }
            }
        }
        .confirmationDialog("Delete promotion?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete promotion", role: .destructive) {
                Task { if await vm.actions.delete(ids: [promotion.id]).contains(promotion.id) { model.refresh(vm.shop.id); dismiss() } }
            }
        } message: { Text("Its discounts and individual codes will also be permanently deleted.") }
        .confirmationDialog("Delete discount?", isPresented: Binding(get: { discountToDelete != nil }, set: { if !$0 { discountToDelete = nil } }), titleVisibility: .visible) {
            if let discount = discountToDelete {
                Button("Delete discount", role: .destructive) {
                    Task { if await vm.actions.deleteDiscount(promotion: promotion, id: discount.id) { saved() }; discountToDelete = nil }
                }
            }
        }
        .alert("Couldn't update promotion", isPresented: Binding(get: { vm.actions.error != nil && sheet == nil }, set: { if !$0 { vm.actions.error = nil } })) {
            Button("OK", role: .cancel) { vm.actions.error = nil }
        } message: { Text(vm.actions.error ?? "") }
    }
    private var sections: some View {
        Picker("Promotion section", selection: $tab) {
            ForEach(PromotionSection.allCases) { Text($0.title).tag($0).accessibilityIdentifier("promotion.tab.\($0.rawValue)") }
        }.accessibilityIdentifier("promotion.section")
    }
    private func saved() { model.refresh(vm.shop.id); Task { await vm.load() } }
}

private enum PromotionSection: String, CaseIterable, Identifiable {
    case overview, discounts, conditions, codes
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self { case .overview: "Overview"; case .discounts: "Discounts"; case .conditions: "Conditions"; case .codes: "Codes" }
    }
}
private enum PromotionDetailSheet: Identifiable {
    case settings, conditions, discount(PromotionDiscount?), generate
    var id: String {
        switch self { case .settings: "settings"; case .conditions: "conditions"; case .discount(let value): "discount-" + (value?.id ?? "new"); case .generate: "generate" }
    }
}
