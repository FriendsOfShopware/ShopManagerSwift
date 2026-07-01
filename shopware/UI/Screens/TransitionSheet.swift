import SwiftUI
import ShopwareAdminAPI

/// Identifies a pending state transition (the state being changed + the chosen action). Shared by
/// `OrderDetailView` (which presents the sheet) and `TransitionSheet` (which consumes it).
struct TransitionContext: Identifiable {
    let state: OrderStateInfo
    let transition: StateTransition
    var id: String { "\(state.id):\(transition.actionName)" }
}

/// Confirmation-mail options for a state transition: send-confirmation-email toggle (default on),
/// a checklist of the order's documents to attach, and an internal-comment field — mirroring the
/// admin's two-phase state-change dialog.
struct TransitionSheet: View {
    let detail: OrderDetail
    let context: TransitionContext
    let onConfirm: (_ sendMail: Bool, _ documentIds: [String], _ comment: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sendMail = true
    @State private var selectedDocs: Set<String> = []
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Action", value: context.transition.displayName)
                    LabeledContent("Applies to", value: context.state.label)
                }

                Section {
                    Toggle("Send confirmation email", isOn: $sendMail)
                }

                if sendMail, !detail.documents.isEmpty {
                    Section("Attach documents") {
                        ForEach(detail.documents) { doc in
                            Button {
                                if selectedDocs.contains(doc.id) { selectedDocs.remove(doc.id) }
                                else { selectedDocs.insert(doc.id) }
                            } label: {
                                HStack {
                                    Text("\(doc.typeName) \(doc.number)").foregroundStyle(.primary)
                                    Spacer()
                                    if selectedDocs.contains(doc.id) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Internal comment") {
                    TextField("Optional note", text: $comment, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .groupedFormStyle()
            .navigationTitle(context.transition.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onConfirm(
                            sendMail,
                            sendMail ? Array(selectedDocs) : [],
                            comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment
                        )
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
