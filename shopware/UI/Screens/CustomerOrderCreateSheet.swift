import SwiftUI
import ShopwareAdminAPI

struct CustomerOrderCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shop: ConnectedShop
    let onCreated: (String) -> Void
    @State private var model: CustomerOrderCreateModel
    @State private var choosingProducts = false
    @State private var confirmCreate = false
    @State private var confirmCancel = false
    @State private var promotion = ""

    init(api: ShopApi, shop: ConnectedShop, customer: CustomerDetail, onCreated: @escaping (String) -> Void) {
        self.shop = shop
        self.onCreated = onCreated
        _model = State(initialValue: CustomerOrderCreateModel(api: api, customer: customer))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    LabeledContent(model.customer.name, value: model.customer.email)
                    LabeledContent("Sales channel", value: model.customer.salesChannel)
                }
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        if !model.ready { Button("Retry") { Task { await model.start() } }.disabled(model.busy) }
                        else if !model.checkoutUncertain {
                            Button("Reload cart") { Task { await model.reloadCart() } }.disabled(model.busy)
                        }
                        Button("Close without clearing cart") { dismiss() }.disabled(model.busy)
                    }
                }
                if model.ready {
                    contextSection
                    itemsSection
                    if let cart = model.cart {
                        Section("Review order") {
                            ForEach(Array(cart.messages.enumerated()), id: \.offset) { _, message in
                                Label(message.string("message") ?? message.string("messageKey") ?? String(localized: "Cart validation failed"), systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(message.boolean("blockOrder") == true ? .red : .secondary)
                            }
                            LabeledContent("Shipping", value: shop.fmt(cart.shipping, iso: model.currencyIso))
                            LabeledContent("Total", value: shop.fmt(cart.total, iso: model.currencyIso)).font(.headline)
                            Toggle("Send order confirmation email", isOn: $model.sendMail)
                            Text("Creating the order saves it in Shopware. Payment collection is handled by the selected payment method.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.busy { ProgressView(model.ready ? "Updating order…" : "Preparing customer cart…") }
            }
            .groupedFormStyle()
            .disabled(model.busy)
            .navigationTitle("Create order")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if model.cart?.items.isEmpty == false && !model.checkoutUncertain { confirmCancel = true }
                        else { close() }
                    }.disabled(model.busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create order") { confirmCreate = true }.disabled(!model.canCreate)
                }
            }
            .task { await model.start() }
            .sheet(isPresented: $choosingProducts) {
                CustomerEntitySelectionSheet(api: model.api, entity: "product", title: String(localized: "Add products"), multiple: true, selected: []) { ids in
                    Task { await model.addProducts(ids) }
                }
            }
            .confirmationDialog("Create this order for \(model.customer.name)?", isPresented: $confirmCreate, titleVisibility: .visible) {
                Button("Create order") {
                    Task {
                        if let id = await model.create() { onCreated(id); dismiss() }
                    }
                }
            } message: {
                Text("Total: \(shop.fmt(model.cart?.total ?? 0, iso: model.currencyIso)). \(model.sendMail ? String(localized: "An order confirmation email will be sent.") : String(localized: "No order confirmation email will be sent."))")
            }
            .confirmationDialog("Discard this order draft?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive, action: close)
            }
        }
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 560, idealHeight: 760)
        #endif
    }

    private var contextSection: some View {
        Section("Addresses and payment") {
            contextPicker("Billing address", field: "billingAddressId")
            contextPicker("Shipping address", field: "shippingAddressId")
            contextPicker("Payment method", field: "paymentMethodId")
            contextPicker("Shipping method", field: "shippingMethodId")
            contextPicker("Currency", field: "currencyId")
            contextPicker("Language", field: "languageId")
        }
    }

    private func contextPicker(_ title: LocalizedStringKey, field: String) -> some View {
        Picker(title, selection: Binding(get: { model.contextValues[field] ?? "" }, set: { id in
            Task { await model.changeContext(field: field, id: id) }
        })) {
            Text("Choose…").tag("")
            ForEach(model.choices[field] ?? []) { option in Text(option.name).tag(option.id) }
        }
    }

    private var itemsSection: some View {
        Section("Items") {
            Button("Add products…", systemImage: "plus") { choosingProducts = true }
            ForEach(model.cart?.items ?? [], id: \.id) { item in
                CustomerCartItemRow(item: item, shop: shop, currencyIso: model.currencyIso) { amount in
                    Task { await model.quantity(id: item.id ?? "", amount: amount) }
                } onRemove: {
                    Task { await model.remove(id: item.id ?? "") }
                }
            }
            HStack {
                TextField("Promotion code", text: $promotion)
                Button("Apply code") { Task { await model.promotion(code: promotion); promotion = "" } }
                    .disabled(promotion.trimmed.isEmpty)
            }
        }
    }

    private func close() {
        Task { if await model.cancel() { dismiss() } }
    }
}
