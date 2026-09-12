import SwiftUI
import ShopwareAdminAPI

enum OrderBulkAction: String, Identifiable { case status, delete; var id: Self { self } }

/// Keeps successful orders out of subsequent attempts; re-reads transitions before retrying a lost response.
@MainActor @Observable
final class OrderBulkModel {
    let api: ShopApi
    let orders: [RecentOrder]
    var entity = "order"
    var selectedAction = ""
    var sendMail = false
    private(set) var pending: Set<String>
    private(set) var succeeded = Set<String>()
    private(set) var states: [String: OrderStateInfo] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var busy = false
    private(set) var ready = false
    private(set) var permissions = AdminPermissions()
    private var expectedTargets: [String: String] = [:]

    init(api: ShopApi, orders: [RecentOrder]) { self.api = api; self.orders = orders; pending = Set(orders.map(\.id)) }
    var transitions: [StateTransition] {
        guard ready, states.count == pending.count, let first = states.values.first else { return [] }
        return first.transitions.filter { candidate in states.values.allSatisfy { $0.transitions.contains { $0.actionName == candidate.actionName } } }
            .sorted { $0.displayName < $1.displayName }
    }
    var canTransition: Bool {
        permissions.allows("order:update") && permissions.allows(entity + ":update") && permissions.allows("state_machine_history:create") && ready && !busy && transitions.contains { $0.actionName == selectedAction }
    }

    func load() async {
        guard !busy else { return }
        busy = true; ready = false; states = [:]; errors = [:]; defer { busy = false }
        do { permissions = try await api.permissions() }
        catch { errors["permissions"] = message(error); return }
        for id in pending.sorted() {
            do {
                let detail = try await api.fetchOrderDetail(id)
                let state: OrderStateInfo?
                if entity == "order_transaction" { state = detail.payments.first { $0.primary }?.state }
                else if entity == "order_delivery" { state = detail.deliveries.first { $0.primary }?.state }
                else { state = detail.states.first { $0.entity == "order" } }
                guard let state else { throw ApiError.unexpected(status: 400, message: String(localized: "This order has no matching payment or delivery.")) }
                if let expected = expectedTargets[id], state.stateTechnical == expected {
                    pending.remove(id); succeeded.insert(id); expectedTargets[id] = nil
                    continue
                }
                if let error = state.transitionsError { errors[id] = error }
                else { states[id] = state }
            } catch { errors[id] = message(error) }
        }
        ready = errors.isEmpty
        if !transitions.contains(where: { $0.actionName == selectedAction }) { selectedAction = "" }
    }

    func apply() async {
        guard canTransition else { return }
        busy = true; errors = [:]; defer { busy = false }
        for id in pending.sorted() {
            guard let state = states[id], let transition = state.transitions.first(where: { $0.actionName == selectedAction }) else { continue }
            expectedTargets[id] = transition.toStateName
            do {
                try await api.stateMachine.transitionWithOptions(entity: entity, entityId: state.entityId, actionName: selectedAction,
                                                                 sendMail: sendMail, documentIds: [], internalComment: nil)
                pending.remove(id); succeeded.insert(id); expectedTargets[id] = nil
            } catch { errors[id] = message(error) }
        }
        ready = false
    }

    func delete() async {
        guard !busy, permissions.allows("order:delete") else { return }
        busy = true; errors = [:]; defer { busy = false }
        for id in pending.sorted() {
            do { try await api.repository("order").delete(id); pending.remove(id); succeeded.insert(id) }
            catch ApiError.notFound { pending.remove(id); succeeded.insert(id) }
            catch { errors[id] = message(error) }
        }
    }
    private func message(_ error: Error) -> String { (error as? ApiError)?.message ?? error.localizedDescription }
}

struct OrderBulkSheet: View {
    let action: OrderBulkAction
    let updated: (Set<String>) -> Void
    @State private var model: OrderBulkModel
    @State private var confirmation = false
    @Environment(\.dismiss) private var dismiss
    init(api: ShopApi, action: OrderBulkAction, orders: [RecentOrder], updated: @escaping (Set<String>) -> Void) {
        self.action = action; self.updated = updated; _model = State(initialValue: OrderBulkModel(api: api, orders: orders))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(model.pending.count) orders remaining")
                    if action == .status {
                        Picker("Change status for", selection: $model.entity) {
                            Text("Order").tag("order"); Text("Payment").tag("order_transaction"); Text("Delivery").tag("order_delivery")
                        }.disabled(!model.succeeded.isEmpty)
                        Picker("New status", selection: $model.selectedAction) {
                            Text("Select a status").tag("")
                            ForEach(model.transitions, id: \.actionName) { Text($0.displayName).tag($0.actionName) }
                        }
                        if model.ready && model.transitions.isEmpty && !model.pending.isEmpty {
                            Text("The selected orders have no shared status action. Select orders with compatible statuses.").foregroundStyle(.secondary)
                        }
                        Toggle("Send status emails", isOn: $model.sendMail)
                        Text("Payment and delivery actions apply to the current payment or delivery for each order.").font(.callout).foregroundStyle(.secondary)
                    } else { Text("The selected orders and their related records will be permanently deleted.").foregroundStyle(.secondary) }
                }
                ForEach(model.orders) { order in
                    HStack(alignment: .top) {
                        Text("#\(order.orderNumber)")
                        Spacer()
                        if model.succeeded.contains(order.id) { Label("Completed", systemImage: "checkmark.circle").foregroundStyle(.green) }
                        else if let error = model.errors[order.id] { Text(error).foregroundStyle(.red) }
                        else { Text(order.customer).foregroundStyle(.secondary) }
                    }
                }
                if let error = model.errors["permissions"] { Text(error).foregroundStyle(.red) }
                if !model.ready && !model.busy && !model.pending.isEmpty {
                    Button("Reload remaining orders") { Task { await model.load(); updated(model.succeeded) } }.accessibilityIdentifier("orders.bulk.reload")
                }
                if model.busy { ProgressView("Updating orders…") }
            }.groupedFormStyle().disabled(model.busy)
                .navigationTitle(action == .status ? "Change order statuses" : "Delete orders")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { updated(model.succeeded); dismiss() }.disabled(model.busy).accessibilityIdentifier("orders.bulk.done") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action == .status ? "Apply changes" : "Delete orders", role: action == .delete ? .destructive : nil) { confirmation = true }
                            .disabled(model.pending.isEmpty || model.busy || (action == .status ? !model.canTransition : !model.permissions.allows("order:delete")))
                            .accessibilityIdentifier("orders.bulk.apply")
                    }
                }
                .confirmationDialog(action == .status ? "Update the selected orders?" : "Permanently delete the selected orders?", isPresented: $confirmation, titleVisibility: .visible) {
                    Button(action == .status ? "Apply changes" : "Delete orders", role: action == .delete ? .destructive : nil) {
                        Task { if action == .status { await model.apply() } else { await model.delete() }; updated(model.succeeded) }
                    }.accessibilityIdentifier("orders.bulk.confirm")
                } message: {
                    if action == .status { Text(model.sendMail ? "Customers will receive status emails." : "No status emails will be sent.") }
                    else { Text("This cannot be undone.") }
                }
        }
        .task(id: model.entity) { await model.load() }
        .interactiveDismissDisabled().acceptsFirstMouse()
        #if os(macOS)
        .frame(width: 600, height: 520)
        #endif
    }
}
