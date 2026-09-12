import SwiftUI
import ShopwareAdminAPI

struct PromotionEditorSheet: View {
    let promotion: PromotionItem?
    let fields: [CustomerCustomFieldSet]
    @Bindable var actions: PromotionActions
    let onSave: (String) -> Void
    @State private var creationFields: [CustomerCustomFieldSet] = []
    @State private var fieldsLoaded = false
    @State private var fieldsError: String?
    @Environment(\.locale) private var locale
    private var effectiveFields: [CustomerCustomFieldSet] { promotion == nil ? creationFields : fields }
    @State private var original: PromotionDraft
    @State private var id: String
    @State private var draft: PromotionDraft
    init(promotion: PromotionItem?, fields: [CustomerCustomFieldSet], actions: PromotionActions, onSave: @escaping (String) -> Void) {
        self.promotion = promotion; self.fields = fields; self.actions = actions; self.onSave = onSave
        let original = PromotionDraft(promotion); _original = State(initialValue: original); _draft = State(initialValue: original)
        _id = State(initialValue: promotion?.id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
    }
    var body: some View {
        PromotionFormSheet(title: promotion == nil ? "New promotion" : "Edit promotion", busy: actions.busy,
                           changed: draft != original,
                           canSave: (promotion != nil || fieldsLoaded) && draft != original && draft.validationError(sets: effectiveFields) == nil && (promotion == nil ? actions.canCreate : actions.canEdit),
                           error: actions.error, saveTitle: promotion == nil ? "Create" : "Save") {
            let success = await actions.save(id: id, draft: draft, fields: effectiveFields, creating: promotion == nil)
            if success { onSave(id) }
            return success
        } content: {
            if let fieldsError { Section { PromotionNotice(message: fieldsError) { Task { await loadCreationFields() } } } }
            if promotion == nil && !fieldsLoaded && fieldsError == nil { ProgressView("Loading fields…") }
            Section("General") {
                LabeledContent("Name") { TextField("Promotion name", text: $draft.name).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.edit.name") }
                Toggle("Enabled", isOn: $draft.active).accessibilityIdentifier("promotion.edit.active")
                LabeledContent("Priority") { TextField("Priority", text: $draft.priority).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.edit.priority") }
            }
            Section("Schedule") {
                Toggle("Set a start date", isOn: $draft.hasStart).accessibilityIdentifier("promotion.edit.hasStart")
                if draft.hasStart { DatePicker("Starts", selection: $draft.starts) }
                Toggle("Set an end date", isOn: $draft.hasEnd).accessibilityIdentifier("promotion.edit.hasEnd")
                if draft.hasEnd { DatePicker("Ends", selection: $draft.ends) }
            }
            Section {
                LabeledContent("Total redemptions") { TextField("Unlimited", text: $draft.globalLimit).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.edit.globalLimit") }
                LabeledContent("Per customer") { TextField("Unlimited", text: $draft.customerLimit).labelsHidden().multilineTextAlignment(.trailing).accessibilityIdentifier("promotion.edit.customerLimit") }
            } header: { Text("Redemption limits") } footer: { Text("Leave a limit empty for unlimited redemptions.") }
            Section {
                Picker("Code type", selection: $draft.codeMode) { ForEach(PromotionCodeMode.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("promotion.edit.codeMode")
                if draft.codeMode == .fixed {
                    LabeledContent("Promotion code") { TextField("Code", text: $draft.code).labelsHidden().autocorrectionDisabled().accessibilityIdentifier("promotion.edit.code") }
                }
                if draft.codeMode == .individual {
                    LabeledContent("Code pattern") { TextField("Code pattern", text: $draft.codePattern).labelsHidden().autocorrectionDisabled().accessibilityIdentifier("promotion.edit.pattern") }
                    Text("Use %s for a letter and %d for a digit, with an optional prefix and suffix.").font(.callout).foregroundStyle(.secondary)
                }
                if let promotion, promotion.codeMode == .individual && draft.codeMode != .individual {
                    Text("Existing individual codes will be kept, but cannot be redeemed with this code type.").foregroundStyle(.secondary)
                }
            } header: { Text("Promotion codes") }
            CustomerCustomFieldsForm(sets: effectiveFields, api: actions.api, values: $draft.customFields)
            if let error = draft.validationError(sets: effectiveFields) { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("promotion.validationError") } }
        }.onAppear { actions.error = nil }
            .task { if promotion == nil { await loadCreationFields() } }
    }
    private func loadCreationFields() async {
        fieldsError = nil
        do {
            if actions.permissions.allows("custom_field_set:read") {
                creationFields = try await actions.api.customerCustomFieldSets(entity: "promotion", locale: locale.identifier)
            }
            fieldsLoaded = true
        } catch { fieldsError = error.localizedDescription; fieldsLoaded = false }

    }
}
