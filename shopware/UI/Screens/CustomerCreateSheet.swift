import SwiftUI
import ShopwareAdminAPI

struct CustomerCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let api: ShopApi
    let permissions: AdminPermissions
    let onCreated: (String) -> Void
    @State private var draft = CustomerCreateDraft()
    @State private var options: CustomerEditorOptions?
    @State private var channels: [CustomerOption] = []
    @State private var countries: [CountryOption] = []
    @State private var states: [CustomerOption] = []
    @State private var boundToSalesChannel = false
    @State private var loading = true
    @State private var loadingChannel = false
    @State private var loadingStates = false
    @State private var saving = false
    @State private var error: String?
    @State private var channelError: String?
    @State private var stateError: String?
    @State private var reservedNumber: String?
    @State private var sameRecipient = true
    @State private var discard = false
    @State private var addressCustomFieldSets: [CustomerCustomFieldSet] = []

    private var validation: String? {
        draft.validationError(country: countries.first { $0.id == draft.address.countryId })
            ?? options?.customFieldSets.flatMap(\.fields).compactMap { $0.validationError(draft.customer.customFields[$0.name]) }.first
            ?? addressCustomFieldSets.flatMap(\.fields).compactMap { $0.validationError(draft.address.customFields[$0.name]) }.first
    }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    ProgressView("Loading customer options…")
                } else if let options {
                    Section("Registration") {
                        Picker("Sales channel", selection: $draft.customer.salesChannelId) {
                            Text("Select a sales channel").tag("")
                            ForEach(channels) { Text($0.name).tag($0.id) }
                        }
                        .accessibilityIdentifier("customer.salesChannel")
                        if boundToSalesChannel { Text("Login will be limited to the selected sales channel.").foregroundStyle(.secondary) }
                        TextField("Customer number", text: $draft.customer.customerNumber, prompt: Text("Generated automatically"))
                            .accessibilityLabel("Customer number")
                        Toggle("Guest customer", isOn: $draft.customer.guest)
                            .accessibilityIdentifier("customer.guest")
                        if !draft.customer.guest {
                            SecureField("Password", text: $draft.password)
                            SecureField("Confirm password", text: $draft.passwordConfirmation)
                        }
                    }
                    CustomerGeneralForm(customer: $draft.customer, options: options, permissions: permissions, api: api)
                    Section {
                        Toggle("Use customer details as the address recipient", isOn: $sameRecipient)
                    } header: { Text("Default billing & shipping address") }
                    CustomerAddressFields(address: $draft.address, countries: countries, states: states,
                                          salutations: options.salutations, showRecipient: !sameRecipient)
                    CustomerCustomFieldsForm(sets: addressCustomFieldSets, api: api, values: $draft.address.customFields)
                    if let validation { Section { Text(validation).foregroundStyle(.secondary) } }
                }
                if loadingChannel || loadingStates { ProgressView("Loading available options…") }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if options == nil { Button("Retry") { Task { await load() } } }
                    }
                }
                if let channelError {
                    Section { Text(channelError).foregroundStyle(.red); Button("Retry sales channel") { Task { await loadChannel() } } }
                }
                if let stateError {
                    Section { Text(stateError).foregroundStyle(.red); Button("Retry states") { Task { await loadStates() } } }
                }
            }
            .disabled(saving).groupedFormStyle()
            .navigationTitle("Add customer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) {
                        HStack { if saving { ProgressView().controlSize(.small) }; Text("Add customer") }
                    }
                    .disabled(saving || loading || loadingChannel || loadingStates || options == nil || validation != nil || channelError != nil || stateError != nil)
                    .accessibilityIdentifier("customer.create.save")
                }
            }
            .task { await load() }
            .task(id: draft.customer.salesChannelId) { await loadChannel() }
            .task(id: draft.address.countryId) { await loadStates() }
            .onChange(of: [draft.customer.firstName, draft.customer.lastName, draft.customer.company ?? "", draft.customer.salutationId ?? "", draft.customer.title ?? ""], syncRecipient)
            .onChange(of: sameRecipient, syncRecipient)
            .onChange(of: draft.address.countryId) { draft.address.countryStateId = nil }
            .confirmationDialog("Discard new customer?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(minWidth: 580, idealWidth: 660, minHeight: 560, idealHeight: 760)
        #endif
    }

    private func load() async {
        guard options == nil else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let channels = api.customerOptions("sales-channel", criteria: Criteria().addSorting("name"))
            async let countries = api.fetchCountries()
            async let bound = api.customers.registrationIsBoundToSalesChannel()
            self.channels = try await channels
            self.countries = try await countries
            boundToSalesChannel = try await bound
            if permissions.allows("custom_field_set:read") {
                addressCustomFieldSets = try await api.customerCustomFieldSets(entity: "customer_address", locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
            }
            options = try await CustomerEditorOptions.load(api: api, customer: draft.customer, permissions: permissions)
            if let salutation = try await api.repository("salutation").search(Criteria().setLimit(1)
                .addFilter(Criteria.equals("salutationKey", "not_specified"))).data.first {
                draft.customer.salutationId = salutation.id
                syncRecipient()
            }
        } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }

    private func loadChannel() async {
        let id = draft.customer.salesChannelId
        channelError = nil
        reservedNumber = nil
        guard !id.isEmpty else { loadingChannel = false; return }
        loadingChannel = true
        defer { if draft.customer.salesChannelId == id { loadingChannel = false } }
        do {
            let channel = try await api.repository("sales-channel").get(id)
            var customer = draft.customer
            customer.groupId = channel?.string("customerGroupId") ?? customer.groupId
            customer.languageId = channel?.string("languageId") ?? customer.languageId
            let loaded = try await CustomerEditorOptions.load(api: api, customer: customer, permissions: permissions)
            guard draft.customer.salesChannelId == id, !Task.isCancelled else { return }
            draft.customer.groupId = customer.groupId
            draft.customer.languageId = customer.languageId
            options = loaded
            if draft.address.countryId == nil { draft.address.countryId = channel?.string("countryId") }
        } catch is CancellationError { return }
        catch { if draft.customer.salesChannelId == id { channelError = (error as? ApiError)?.message ?? error.localizedDescription } }
    }

    private func loadStates() async {
        let id = draft.address.countryId
        states = []
        stateError = nil
        guard let id, !id.isEmpty else { loadingStates = false; return }
        loadingStates = true
        defer { if draft.address.countryId == id { loadingStates = false } }
        do {
            let loaded = try await api.customerOptions("country-state", criteria: Criteria().addSorting("name").addFilter(Criteria.equals("countryId", .string(id))))
            guard draft.address.countryId == id, !Task.isCancelled else { return }
            states = loaded
        } catch is CancellationError { return }
        catch { if draft.address.countryId == id { stateError = (error as? ApiError)?.message ?? error.localizedDescription } }
    }

    private func syncRecipient() {
        guard sameRecipient else { return }
        draft.address.firstName = draft.customer.firstName
        draft.address.lastName = draft.customer.lastName
        draft.address.company = draft.customer.company
        draft.address.salutationId = draft.customer.salutationId
        draft.address.title = draft.customer.title
    }

    private func create() {
        guard !saving, validation == nil, permissions.allows("customer:create") else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                var number = draft.customer.customerNumber.trimmed
                if number.isEmpty {
                    if reservedNumber == nil { reservedNumber = try await api.customers.reserveNumber(salesChannelId: draft.customer.salesChannelId) }
                    number = reservedNumber ?? ""
                }
                try await api.repository("customer").create(draft.payload(number: number, boundToSalesChannel: boundToSalesChannel))
                onCreated(draft.customer.id)
                dismiss()
            } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
