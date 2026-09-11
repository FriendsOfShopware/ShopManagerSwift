import SwiftUI
import ShopwareAdminAPI

struct CustomerAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: CustomerDetailViewModel
    let request: CustomerAddressEdit
    let onSaved: () -> Void
    @State private var address: EditableAddress
    @State private var countries: [CountryOption] = []
    @State private var states: [CustomerOption] = []
    @State private var salutations: [SalutationOption] = []
    @State private var defaultBilling: Bool
    @State private var defaultShipping: Bool
    @State private var loading = true
    @State private var loadingStates = false
    @State private var saving = false
    @State private var error: String?
    @State private var stateError: String?
    @State private var optionsLoaded = false
    @State private var showDiscard = false
    @State private var customFieldSets: [CustomerCustomFieldSet] = []

    init(vm: CustomerDetailViewModel, request: CustomerAddressEdit, onSaved: @escaping () -> Void) {
        self.vm = vm
        self.request = request
        self.onSaved = onSaved
        _address = State(initialValue: request.address)
        _defaultBilling = State(initialValue: vm.detail?.defaultBillingAddressId == request.address.id)
        _defaultShipping = State(initialValue: vm.detail?.defaultShippingAddressId == request.address.id)
    }

    private var validation: String? {
        address.validationError(country: countries.first { $0.id == address.countryId }, business: vm.detail?.accountType == "business")
            ?? customFieldSets.flatMap(\.fields).compactMap { $0.validationError(address.customFields[$0.name]) }.first
    }

    private var changed: Bool {
        request.isNew || address != request.address
            || defaultBilling != (vm.detail?.defaultBillingAddressId == address.id)
            || defaultShipping != (vm.detail?.defaultShippingAddressId == address.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    ProgressView("Loading address options…")
                } else if optionsLoaded {
                    CustomerAddressFields(address: $address, countries: countries, states: states, salutations: salutations)
                    CustomerCustomFieldsForm(sets: customFieldSets, api: vm.api, values: $address.customFields)
                    Section {
                        Toggle("Default billing address", isOn: $defaultBilling)
                            .disabled(vm.detail?.defaultBillingAddressId == address.id || !vm.permissions.allows("customer:update"))
                        Toggle("Default shipping address", isOn: $defaultShipping)
                            .disabled(vm.detail?.defaultShippingAddressId == address.id || !vm.permissions.allows("customer:update"))
                    } header: { Text("Use as default") } footer: {
                        Text("To replace an existing default, choose another address as the default.")
                    }
                    if loadingStates { ProgressView("Loading states…") }
                    if let validation { Section { Text(validation).foregroundStyle(.secondary) } }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if !optionsLoaded { Button("Retry") { Task { await load() } } }
                    }
                }
                if let stateError {
                    Section {
                        Text(stateError).foregroundStyle(.red)
                        Button("Retry states") { Task { await loadStates() } }
                    }
                }
            }
            .groupedFormStyle()
            .disabled(saving)
            .navigationTitle(request.isNew ? "Add address" : "Edit address")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if changed { showDiscard = true } else { dismiss() }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        HStack {
                            if saving { ProgressView().controlSize(.small) }
                            Text("Save")
                        }
                    }
                    .disabled(saving || !optionsLoaded || loadingStates || stateError != nil || validation != nil || !changed)
                }
            }
            .task { await load() }
            .task(id: address.countryId) { await loadStates() }
            .onChange(of: address.countryId) { old, new in
                if old != new { address.countryStateId = nil }
            }
            .confirmationDialog("Discard address changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled(saving || changed)
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 520, idealHeight: 720)
        #endif
    }

    private func load() async {
        guard !optionsLoaded else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let fetchedCountries = vm.api.fetchCountries()
            async let fetchedSalutations = vm.api.fetchSalutations()
            countries = try await fetchedCountries
            salutations = try await fetchedSalutations
            if vm.permissions.allows("custom_field_set:read") {
                customFieldSets = try await vm.api.customerCustomFieldSets(entity: "customer_address", locale: vm.shop.localeCode ?? "en-GB")
            }
            if let id = address.countryId, !countries.contains(where: { $0.id == id }),
               let current = try await vm.api.repository("country").get(id) {
                countries.append(CountryOption(id: id, name: current.translated("name") ?? id,
                                               postalCodeRequired: current.boolean("postalCodeRequired") ?? false,
                                               forceStateInRegistration: current.boolean("forceStateInRegistration") ?? false))
            }
            optionsLoaded = true
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    private func loadStates() async {
        let countryId = address.countryId
        states = []
        stateError = nil
        guard let countryId, !countryId.isEmpty else { loadingStates = false; return }
        loadingStates = true
        defer { if address.countryId == countryId { loadingStates = false } }
        do {
            let loaded = try await vm.api.customerOptions("country-state", criteria: Criteria()
                .addFilter(Criteria.equals("countryId", .string(countryId))).addSorting("name"))
            guard address.countryId == countryId, !Task.isCancelled else { return }
            states = loaded
        } catch is CancellationError {
            return
        } catch {
            if address.countryId == countryId { stateError = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }

    private func save() {
        guard !saving, validation == nil, vm.permissions.allows("customer:update"),
              vm.permissions.allows(request.isNew ? "customer_address:create" : "customer_address:update") else { return }
        saving = true
        error = nil
        let payload = customerAddressSavePayload(customerId: vm.customerId, address: address,
                                                defaultBilling: defaultBilling, defaultShipping: defaultShipping,
                                                original: request.isNew ? nil : request.address)
        Task {
            defer { saving = false }
            do {
                try await vm.api.customers.save(payload)
                await vm.load()
                vm.addresses.reload()
                onSaved()
                dismiss()
            } catch {
                self.error = (error as? ApiError)?.message ?? error.localizedDescription
            }
        }
    }
}
