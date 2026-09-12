import SwiftUI
import ShopwareAdminAPI

struct OrderEditSheet: View {
    @State private var model: OrderEditModel
    @State private var addingProducts = false
    @State private var itemKind: OrderExtraItemKind?
    @State private var address: EditableAddress?
    @State private var reloadConfirmation = false
    @State private var promotion = ""

    init(vm: OrderDetailViewModel) { _model = State(initialValue: OrderEditModel(owner: vm)) }

    var body: some View {
        OrderFormSheet(title: "Edit order", saveTitle: model.reviewed ? "Save changes" : "Review changes",
                       canSave: model.canSave, busy: model.busy, dirty: model.hasChanges && !model.saveUncertain,
                       error: model.error, save: { await model.save() }, cancel: { await model.discard() }) {
            if let draft = Binding($model.draft) {
                Section {
                    Text(model.reviewed ? "Review the recalculated totals, then save your changes." : "Changes are kept in a draft until you review and save them.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Total", value: model.owner.shop.fmt(draft.wrappedValue.amountTotal, iso: draft.wrappedValue.currencyIso))
                    ForEach(model.issues) { issue in
                        Label(issue.message, systemImage: issue.blocksOrder ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(issue.blocksOrder ? .red : .secondary)
                    }
                    if model.requiresReload {
                        Text("The previous request could not be confirmed. Reload the server draft before making more changes.")
                        Button("Reload draft") { reloadConfirmation = true }
                    }
                }
                Group {
                    Section("Order items") {
                        ForEach(draft.lineItems) { item in
                            OrderEditableItemRow(item: item, canEdit: allows("order_line_item:update"),
                                                 canRemove: allows("order_line_item:delete"),
                                                 quantity: { model.setQuantity(id: item.wrappedValue.id, quantity: $0) },
                                                 remove: { model.removeItem(item.wrappedValue.id) })
                        }
                        Menu("Add item", systemImage: "plus") {
                            Button("Products…") { addingProducts = true }.disabled(!allows("product:read"))
                            Button("Custom item…") { itemKind = .custom }
                            Button("Credit…") { itemKind = .credit }.disabled(!allows("order:create:discount"))
                        }.disabled(!allows("order_line_item:create")).accessibilityIdentifier("order.editor.addItem")
                    }
                    Section("Promotions") {
                        OrderLabeledField("Promotion code") {
                            TextField("Promotion code", text: $promotion).autocorrectionDisabled()
                        }
                        Button("Apply promotion") { Task { await model.addPromotion(promotion); if model.error == nil { promotion = "" } } }
                            .disabled(promotion.trimmed.isEmpty)
                        Button("Apply automatic promotions") { Task { await model.applyAutomaticPromotions() } }
                    }.disabled(!allows("order_line_item:create") || !allows("order:create:discount"))
                    if let billing = draft.wrappedValue.billing {
                        Section("Billing address") {
                            Text(billing.formatted)
                            Button("Edit billing address…") { address = billing }.disabled(!allows("order_address:update"))
                        }
                    }
                    ForEach(draft.deliveries) { delivery in
                        Section(delivery.wrappedValue.method) {
                            if let recipient = delivery.wrappedValue.address {
                                Text(recipient.formatted)
                                Button("Edit shipping address…") { address = recipient }.disabled(!allows("order_address:update"))
                            }
                            OrderLabeledField("Shipping costs") {
                                TextField("Shipping costs", value: shippingCost(delivery), format: .number)
                                    .disabled(!allows("order_delivery:update"))
                            }
                        }
                    }
                    Section("Contact & notes") {
                        OrderLabeledField("Email") {
                            TextField("Email", text: draft.customerEmail).textContentType(.emailAddress)
                                .disabled(!allows("order_customer:update")).accessibilityIdentifier("order.editor.email")
                        }
                        OrderLabeledField("Customer comment") {
                            TextField("Customer comment", text: draft.customerComment.orEmpty, axis: .vertical).lineLimit(2...6)
                        }
                        OrderLabeledField("Internal note") {
                            TextField("Internal note", text: draft.internalComment.orEmpty, axis: .vertical).lineLimit(2...6)
                                .accessibilityIdentifier("order.editor.note")
                        }
                    }
                    Section("Attribution") {
                        OrderLabeledField("Affiliate code") { TextField("Affiliate code", text: draft.affiliateCode) }
                        OrderLabeledField("Campaign code") { TextField("Campaign code", text: draft.campaignCode) }
                    }
                    if allows("tag:read") {
                        Section("Tags") {
                            CustomerTagsField(tags: draft.tags, knownTags: model.knownTags, api: model.api, canCreate: allows("tag:create"))
                        }.disabled(!allows("order_tag:create") || !allows("order_tag:delete"))
                    }
                    CustomerCustomFieldsForm(sets: model.owner.customFieldSets, api: model.api, values: draft.customFields)
                }.disabled(model.requiresReload || model.saveUncertain)
            } else if !model.busy {
                Button("Retry loading draft") { Task { await model.start() } }
            }
        }
        .task { await model.start() }
        .sheet(isPresented: $addingProducts) {
            CustomerEntitySelectionSheet(api: model.api, entity: "product", title: String(localized: "Add products"), multiple: true, selected: []) {
                ids in Task { await model.addProducts(ids) }
            }
        }
        .sheet(item: $itemKind) { OrderExtraItemSheet(model: model, kind: $0) }
        .sheet(item: $address) { initial in OrderAddressSheet(api: model.api, initial: initial, save: model.updateAddress) }
        .confirmationDialog("Reload the server draft?", isPresented: $reloadConfirmation, titleVisibility: .visible) {
            Button("Reload draft") { Task { await model.reloadDraft() } }
        } message: { Text("Changes already received by the server will be kept. Unsaved changes in this form will be replaced.") }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 700, minHeight: 360, idealHeight: 720)
        #endif
    }

    private func allows(_ privilege: String) -> Bool { model.owner.permissions.allows(privilege) }
    private func shippingCost(_ delivery: Binding<OrderDelivery>) -> Binding<Double> {
        Binding(get: { delivery.wrappedValue.shippingCosts["totalPrice"]?.doubleValue ?? 0 }, set: { value in
            var costs = delivery.wrappedValue.shippingCosts.objectValue ?? [:]
            costs["totalPrice"] = .number(value); costs["unitPrice"] = .number(value)
            delivery.wrappedValue.shippingCosts = .object(costs)
        })
    }
}

private struct OrderEditableItemRow: View {
    @Binding var item: OrderLineItem
    let canEdit: Bool
    let canRemove: Bool
    let quantity: (Int) -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OrderLabeledField("Item name") { TextField("Item name", text: $item.label).disabled(!canEdit) }
            if let number = item.productNumber { Text(number).font(.caption).foregroundStyle(.secondary) }
            if item.type == "promotion" {
                Text("Promotion prices are calculated by the shop.").font(.caption).foregroundStyle(.secondary)
            } else {
                Stepper("Quantity: \(item.quantity)", value: Binding(get: { item.quantity }, set: quantity), in: 1...99999)
                    .disabled(!canEdit || item.parentId != nil).accessibilityIdentifier("order.item.quantity.\(item.id)")
                OrderLabeledField("Unit price") { TextField("Unit price", value: $item.unitPrice, format: .number).disabled(!canEdit) }
            }
            Button("Remove item", systemImage: "trash", role: .destructive, action: remove).disabled(!canRemove)
        }.padding(.vertical, 6)
    }
}

private enum OrderExtraItemKind: String, Identifiable { case custom, credit; var id: Self { self } }

private struct OrderExtraItemSheet: View {
    @Bindable var model: OrderEditModel
    let kind: OrderExtraItemKind
    @State private var label = ""
    @State private var price = 0.0
    @State private var tax = 0.0
    @State private var quantity = 1
    @State private var identifier = UUID().uuidString
    var body: some View {
        OrderFormSheet(title: kind == .credit ? "Add credit" : "Add custom item", saveTitle: "Add item",
                       canSave: !label.trimmed.isEmpty && price.isFinite && price >= 0 && tax >= 0 && tax <= 100 && !model.requiresReload,
                       busy: model.busy, dirty: !label.isEmpty || price != 0, error: model.error,
                       save: { await model.addItem(payload, credit: kind == .credit) }) {
            Section {
                OrderLabeledField("Item name") { TextField("Item name", text: $label) }
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99999)
                OrderLabeledField("Amount per item") { TextField("Amount per item", value: $price, format: .number) }
                OrderLabeledField("Tax rate (%)") { TextField("Tax rate (%)", value: $tax, format: .number) }
                if kind == .credit { Text("The amount will be deducted from the order.").foregroundStyle(.secondary) }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 420)
        #endif
    }
    private var payload: JSONValue {
        .object(["identifier": .string(identifier), "label": .string(label.trimmed), "quantity": .int(quantity),
                 "type": .string(kind.rawValue), "priceDefinition": .object([
                    "price": .number(kind == .credit ? -price : price), "quantity": .int(quantity), "isCalculated": true,
                    "taxRules": .array([.object(["taxRate": .number(tax), "percentage": 100])])])])
    }
}

private struct OrderAddressSheet: View {
    let api: ShopApi
    let initial: EditableAddress
    let save: (EditableAddress) -> Void
    @State private var address: EditableAddress
    @State private var countries: [CountryOption] = []
    @State private var states: [CustomerOption] = []
    @State private var salutations: [SalutationOption] = []
    @State private var busy = false
    @State private var error: String?

    init(api: ShopApi, initial: EditableAddress, save: @escaping (EditableAddress) -> Void) {
        self.api = api; self.initial = initial; self.save = save; _address = State(initialValue: initial)
    }
    var body: some View {
        OrderFormSheet(title: "Edit order address", canSave: !countries.isEmpty, busy: busy, dirty: address != initial, error: error,
                       save: {
            if let message = address.validationError(country: countries.first { $0.id == address.countryId }, business: false) { error = message; return false }
            var result = address
            result.countryName = countries.first { $0.id == address.countryId }?.name
            result.countryStateName = states.first { $0.id == address.countryStateId }?.name
            save(result); return true
        }) {
            CustomerAddressFields(address: $address, countries: countries, states: states, salutations: salutations)
            if error != nil { Button("Reload address options") { Task { await load() } } }
        }
        .task { await load() }
        .task(id: address.countryId) { await loadStates() }
        .onChange(of: address.countryId) { address.countryStateId = nil }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 580, minHeight: 360, idealHeight: 680)
        #endif
    }
    private func load() async {
        busy = true; error = nil; defer { busy = false }
        do {
            countries = try await api.fetchCountries()
            if let id = initial.countryId, !countries.contains(where: { $0.id == id }),
               let country = try await api.repository("country").get(id) {
                countries.append(CountryOption(id: id, name: country.translated("name") ?? initial.countryName ?? "—",
                                               postalCodeRequired: country.boolean("postalCodeRequired") ?? false,
                                               forceStateInRegistration: country.boolean("forceStateInRegistration") ?? false))
            }
            salutations = try await api.fetchSalutations()
        }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }
    private func loadStates() async {
        states = []
        guard let id = address.countryId else { return }
        do {
            let result = try await api.customerOptions("country-state", criteria: Criteria().addFilter(Criteria.equals("countryId", .string(id))).addSorting("name"))
            if address.countryId == id { states = result }
        } catch is CancellationError { }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }
}
