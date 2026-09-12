import SwiftUI
import ShopwareAdminAPI

struct ReviewEditorSheet: View {
    let review: ReviewItem
    let fields: [CustomerCustomFieldSet]
    @Bindable var actions: ReviewActions
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReviewDraft
    @State private var discarding = false
    @State private var choosingLanguage = false
    @State private var languageName: String

    init(review: ReviewItem, fields: [CustomerCustomFieldSet], actions: ReviewActions, onSave: @escaping () -> Void) {
        self.review = review; self.fields = fields; self.actions = actions; self.onSave = onSave
        _draft = State(initialValue: ReviewDraft(review)); _languageName = State(initialValue: review.languageName)
    }
    private var changed: Bool { draft != ReviewDraft(review) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Approved", isOn: $draft.approved).accessibilityIdentifier("review.edit.approved")
                    Button { choosingLanguage = true } label: { LabeledContent("Language", value: languageName) }.accessibilityIdentifier("review.edit.language")
                } header: { Text("Properties") } footer: { Text("Approved reviews are visible in the storefront.") }
                Section {
                    TextEditor(text: $draft.comment).frame(minHeight: 140)
                        .accessibilityLabel("Public reply").accessibilityIdentifier("review.edit.reply")
                } header: { Text("Public reply") } footer: { Text("Your reply appears with the approved review in the storefront. Clear the text to remove an existing reply.") }
                CustomerCustomFieldsForm(sets: fields, api: actions.api, values: $draft.customFields)
                if let error = draft.validationError(sets: fields) { Section { Text(error).foregroundStyle(.red) } }
            }.groupedFormStyle().disabled(actions.busy)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = actions.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleAndIcon).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true).padding()
                        .background(.background)
                        .accessibilityIdentifier("review.saveError")
                }
            }
            .navigationTitle("Edit review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if changed { discarding = true } else { dismiss() } }.disabled(actions.busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await actions.save(id: review.id, draft: draft, sets: fields) { onSave(); dismiss() } }
                    }.disabled(!changed || !actions.canEdit || draft.validationError(sets: fields) != nil)
                        .keyboardShortcut("s", modifiers: .command).accessibilityIdentifier("review.edit.save")
                }
            }
            .sheet(isPresented: $choosingLanguage) {
                CustomerEntitySelectionSheet(api: actions.api, entity: "language", title: String(localized: "Language"), multiple: false, selected: [draft.languageId], sortField: "name") {
                    draft.languageId = $0.first ?? ""
                    languageName = draft.languageId.isEmpty ? String(localized: "Choose a language") : "…"
                }
            }
            .task(id: draft.languageId) {
                guard !draft.languageId.isEmpty else { return }
                do {
                    if let language = try await actions.api.repository("language").get(draft.languageId) { languageName = language.translated("name") ?? "—" }
                } catch { languageName = String(localized: "Couldn't load selected items") }
            }
            .confirmationDialog("Discard changes?", isPresented: $discarding, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { actions.error = nil; dismiss() }
            }
            .onAppear { actions.error = nil }
        }
        .interactiveDismissDisabled(changed || actions.busy)
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 580, minHeight: 360, idealHeight: 620)
        .presentationSizing(.fitted)
        #endif
    }
}
