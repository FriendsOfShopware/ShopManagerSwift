import SwiftUI
import ShopwareAdminAPI

struct CustomerBulkEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let api: ShopApi
    let customers: [CustomerRow]
    let permissions: AdminPermissions
    let onSaved: () -> Void
    @State private var draft = CustomerBulkDraft()
    @State private var options: CustomerEditorOptions?
    @State private var saving = false
    @State private var confirm = false
    @State private var completed = Set<String>()
    @State private var savedFields = Set<String>()
    @State private var failures: [String: String] = [:]
    @State private var loadError: String?
    @State private var progress = 0

    private var validation: String? {
        if ["remove", "replace", "clear"].contains(draft.tagMode), !permissions.allows("customer_tag:delete") {
            return String(localized: "Your login cannot remove customer tags.")
        }
        if ["add", "replace"].contains(draft.tagMode), !permissions.allows("customer_tag:create") {
            return String(localized: "Your login cannot assign customer tags.")
        }
        return options?.customFieldSets.flatMap(\.fields).filter { draft.customFields[$0.name] != nil }
            .compactMap { $0.validationError(draft.customFields[$0.name]) }.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Only the fields you choose will change for the selected customers.") }
                if let options {
                    Group {
                        Section("Account") {
                            Picker("Customer group", selection: $draft.groupId) {
                                Text("Keep unchanged").tag("")
                                ForEach(options.groups) { Text($0.name).tag($0.id) }
                            }
                            Picker("Status", selection: Binding(
                                get: { draft.active.map { $0 ? "active" : "disabled" } ?? "" },
                                set: { draft.active = $0.isEmpty ? nil : $0 == "active" }
                            )) {
                                Text("Keep unchanged").tag("")
                                Text("Active").tag("active")
                                Text("Disabled").tag("disabled")
                            }
                            .accessibilityIdentifier("customer.bulk.status")
                            Picker("Language", selection: $draft.languageId) {
                                Text("Keep unchanged").tag("")
                                ForEach(options.languages) { Text($0.name).tag($0.id) }
                            }
                            Picker("Pending group requests", selection: Binding(
                                get: { draft.groupDecision.map { $0 ? "approve" : "decline" } ?? "" },
                                set: { draft.groupDecision = $0.isEmpty ? nil : $0 == "approve" }
                            )) {
                                Text("Keep unchanged").tag("")
                                Text("Approve").tag("approve")
                                Text("Decline").tag("decline")
                            }
                        }
                        Section("Tags") {
                            Picker("Action", selection: $draft.tagMode) {
                                Text("Keep unchanged").tag("unchanged")
                                Text("Add").tag("add")
                                Text("Remove").tag("remove")
                                Text("Replace all").tag("replace")
                                Text("Clear all").tag("clear")
                            }
                            if ["add", "remove", "replace"].contains(draft.tagMode) {
                                CustomerEntityField(label: String(localized: "Tags"), entity: "tag", multiple: true, api: api, value: Binding(
                                    get: { .array(draft.tagIds.sorted().map { .string($0) }) },
                                    set: { draft.tagIds = Set($0?.arrayValue?.compactMap(\.stringValue) ?? []) }
                                ))
                            }
                        }
                        ForEach(options.customFieldSets) { set in
                            Section(set.label) {
                                ForEach(set.fields) { field in
                                    Toggle("Change \(field.label)", isOn: Binding(
                                        get: { draft.customFields[field.name] != nil },
                                        set: { draft.customFields[field.name] = $0 ? .null : nil }
                                    ))
                                    if draft.customFields[field.name] != nil {
                                        CustomerCustomFieldInput(field: field, api: api, value: Binding(
                                            get: { draft.customFields[field.name] }, set: { draft.customFields[field.name] = $0 ?? .null }
                                        ))
                                    }
                                }
                            }
                        }
                    }.disabled(saving || !savedFields.isEmpty || !completed.isEmpty)
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                } else { ProgressView("Loading bulk edit options…") }
                if let validation { Text(validation).foregroundStyle(.red) }
                if saving { ProgressView("Processing \(progress) of \(customers.count)", value: Double(progress), total: Double(customers.count)) }
                if !completed.isEmpty || !failures.isEmpty {
                    Section("Results") {
                        Text("\(completed.count) completed; \(failures.count) failed.")
                        ForEach(customers.filter { failures[$0.id] != nil }) { customer in
                            Text("\(customer.name): \(failures[customer.id] ?? "")").foregroundStyle(.red)
                        }
                        if !savedFields.isSubset(of: completed) {
                            Text("Some customer fields were saved, but their group request could not be processed. Retry resumes that step.")
                        }
                    }
                }
            }
            .groupedFormStyle().navigationTitle("Edit customers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onSaved(); dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(failures.isEmpty ? "Apply changes" : "Retry failed") { confirm = true }
                        .disabled(saving || options == nil || validation != nil || !draft.hasChanges || completed.count == customers.count)
                        .accessibilityIdentifier("customer.bulk.apply")
                }
            }
            .task { await load() }
            .confirmationDialog("Apply these changes to \(customers.count - completed.count) customers?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Apply changes", action: save)
                    .accessibilityIdentifier("customer.bulk.confirm")
            } message: { Text("Group decisions run Shopware's configured notifications. Completed customers will not be processed again.") }
        }
        .interactiveDismissDisabled(saving)
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 480, idealHeight: 680)
        #endif
    }

    private func load() async {
        guard options == nil else { return }
        loadError = nil
        do {
            options = try await CustomerEditorOptions.load(api: api, customer: CustomerCreateDraft().customer, permissions: permissions)
        } catch { loadError = (error as? ApiError)?.message ?? error.localizedDescription }
    }

    private func save() {
        guard !saving, validation == nil, permissions.allows("customer:update") else { return }
        saving = true
        failures = [:]
        progress = completed.count
        Task {
            defer { saving = false; onSaved() }
            for customer in customers where !completed.contains(customer.id) {
                do {
                    if !savedFields.contains(customer.id) {
                        guard let current = try await api.repository("customer").get(customer.id, criteria: Criteria().addAssociation("tags")) else {
                            throw ApiError.unexpected(status: 404, message: String(localized: "This customer no longer exists."))
                        }
                        let changes = draft.changes(for: current)
                        if (changes.payload.objectValue?.count ?? 0) > 1 || !changes.removedTags.isEmpty {
                            try await api.customers.save(changes.payload, removedTagIds: changes.removedTags)
                        }
                        savedFields.insert(customer.id)
                    }
                    if let decision = draft.groupDecision {
                        try await api.customers.decideGroupRequest(customerIds: [customer.id], accept: decision, skipMissingRequests: true)
                    }
                    completed.insert(customer.id)
                } catch { failures[customer.id] = (error as? ApiError)?.message ?? error.localizedDescription }
                progress += 1
            }
        }
    }
}
