import SwiftUI
import ShopwareAdminAPI

struct CustomerEditSheet: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let permissions: AdminPermissions
    let onSaved: () -> Void
    @State private var draft: CustomerDraft
    @State private var options: CustomerEditorOptions?
    @State private var error: String?
    @State private var saving = false
    @State private var loading = false
    @State private var showDiscard = false

    private var customFieldError: String? {
        draft.tagPermissionError(permissions)
            ?? options?.customFieldSets.flatMap(\.fields).compactMap { $0.validationError(draft.customer.customFields[$0.name]) }.first
    }

    init(shop: ConnectedShop, detail: CustomerDetail, permissions: AdminPermissions, onSaved: @escaping () -> Void) {
        self.shop = shop
        self.permissions = permissions
        self.onSaved = onSaved
        _draft = State(initialValue: CustomerDraft(detail))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let options {
                    CustomerGeneralForm(customer: $draft.customer, options: options, permissions: permissions, api: model.repo.apiFor(shop))
                    if !draft.customer.guest {
                        Section {
                            SecureField("New password", text: $draft.password)
                            SecureField("Confirm password", text: $draft.passwordConfirmation)
                        } header: { Text("Password") } footer: {
                            Text("Leave both fields empty to keep the current password.")
                        }
                    }
                    if let validation = draft.validationError {
                        Section { Label(validation, systemImage: "exclamationmark.circle").foregroundStyle(.secondary) }
                    }
                    if let permissionError = draft.tagPermissionError(permissions) {
                        Section { Label(permissionError, systemImage: "lock").foregroundStyle(.secondary) }
                    }
                } else if loading {
                    ProgressView("Loading customer options…")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if options == nil { Button("Retry") { Task { await loadOptions() } } }
                    }
                }
            }
            .disabled(saving)
            .groupedFormStyle()
            .navigationTitle("Edit customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel).disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        HStack {
                            if saving { ProgressView().controlSize(.small) }
                            Text("Save")
                        }
                    }
                    .disabled(saving || options == nil || draft.validationError != nil || customFieldError != nil || !draft.hasChanges)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .task { await loadOptions() }
            .confirmationDialog("Discard customer changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled(saving || draft.hasChanges)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 740)
        #endif
        .acceptsFirstMouse()
    }

    private func loadOptions() async {
        guard options == nil, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            options = try await CustomerEditorOptions.load(api: model.repo.apiFor(shop), customer: draft.customer, permissions: permissions)
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    private func cancel() {
        if draft.hasChanges { showDiscard = true } else { dismiss() }
    }

    private func save() {
        guard !saving, draft.validationError == nil, customFieldError == nil, permissions.allows("customer:update") else { return }
        saving = true
        error = nil
        let payload = draft.payload
        let removed = draft.removedTagIds
        Task {
            defer { saving = false }
            do {
                try await model.repo.apiFor(shop).customers.save(payload, removedTagIds: removed)
                onSaved()
                dismiss()
            } catch {
                self.error = (error as? ApiError)?.message ?? error.localizedDescription
            }
        }
    }
}
