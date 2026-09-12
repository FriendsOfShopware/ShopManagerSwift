import SwiftUI
import ShopwareAdminAPI

struct TransitionContext: Identifiable {
    let state: OrderStateInfo
    let transition: StateTransition
    var id: String { "\(state.id):\(transition.actionName)" }
}

struct TransitionSheet: View {
    @Bindable var vm: OrderDetailViewModel
    let context: TransitionContext
    @State private var sendMail = true
    @State private var selectedDocs = Set<String>()
    @State private var comment = ""

    var body: some View {
        OrderFormSheet(title: "Change status", saveTitle: "Apply", canSave: vm.canTransition(context.state), busy: vm.busy,
                       dirty: !comment.isEmpty || !selectedDocs.isEmpty, error: vm.actionError,
                       saveIdentifier: "order.transition.apply", save: {
            await vm.transition(entity: context.state.entity, entityId: context.state.entityId,
                                actionName: context.transition.actionName, sendMail: sendMail,
                                documentIds: sendMail ? selectedDocs.sorted() : [], internalComment: comment.trimmed.isEmpty ? nil : comment.trimmed)
        }) {
            Section("Status change") {
                LabeledContent("Applies to", value: context.state.label)
                if let method = context.state.method { Text(method).foregroundStyle(.secondary) }
                LabeledContent("Current status", value: context.state.stateName)
                LabeledContent("New status", value: context.transition.displayName)
            }
            Section {
                Toggle("Send confirmation email", isOn: $sendMail).accessibilityIdentifier("order.transition.email")
            } footer: { Text("Shopware will run the configured flows for this status change.") }
            if sendMail, let documents = vm.detail?.documents, !documents.isEmpty {
                Section("Attach documents") {
                    ForEach(documents) { document in
                        Toggle("\(document.typeName) \(document.number)", isOn: Binding(get: { selectedDocs.contains(document.id) }, set: { selected in
                            if selected { selectedDocs.insert(document.id) } else { selectedDocs.remove(document.id) }
                        })).disabled(!document.hasFile)
                    }
                }
            }
            Section("Internal comment") {
                TextField("Optional note", text: $comment, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("order.transition.comment")
            }
        }.onAppear { vm.actionError = nil }
        #if os(macOS)
        .frame(width: 500, height: 520)
        #endif
    }
}
