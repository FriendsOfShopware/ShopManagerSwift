import SwiftUI

/// iOS text fields use their title as a placeholder, so keep a visible label after editing.
struct OrderLabeledField<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            content.labelsHidden()
        }.padding(.vertical, 4)
        #else
        content
        #endif
    }
}

/// Shared editor chrome keeps fields visible when an asynchronous save fails.
struct OrderFormSheet<Content: View>: View {
    let title: LocalizedStringKey
    var saveTitle: LocalizedStringKey = "Save"
    let canSave: Bool
    let busy: Bool
    let dirty: Bool
    let error: String?
    var saveIdentifier = "order.editor.save"
    let save: () async -> Bool
    var cancel: () async -> Bool = { true }
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                content
            }.groupedFormStyle().disabled(busy).accessibilityIdentifier("order.editor.form")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if error != nil || busy {
                        VStack(alignment: .leading, spacing: 10) {
                            Divider()
                            if let error {
                                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                                    .accessibilityIdentifier("order.editor.error")
                                    .padding(.horizontal).padding(.bottom, 10)
                            }
                            if busy { ProgressView("Updating order…").padding(.horizontal).padding(.bottom, 10) }
                        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background)
                    }
                }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { if dirty { confirmDiscard = true } else { close() } }
                            .disabled(busy).accessibilityIdentifier("order.editor.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle) { Task { if await save() { dismiss() } } }
                            .disabled(!canSave || busy).accessibilityIdentifier(saveIdentifier)
                    }
                }
                .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard changes", role: .destructive, action: close).accessibilityIdentifier("order.editor.discard")
                }
        }.interactiveDismissDisabled().acceptsFirstMouse()
    }

    private func close() { Task { if await cancel() { dismiss() } } }
}

struct OrderNoteSheet: View {
    @Bindable var vm: OrderDetailViewModel
    @State private var text: String
    private let original: String
    init(vm: OrderDetailViewModel) {
        self.vm = vm
        original = vm.detail?.internalComment ?? ""
        _text = State(initialValue: original)
    }
    var body: some View {
        OrderFormSheet(title: "Internal note", canSave: vm.canEdit, busy: vm.busy, dirty: text != original, error: vm.actionError,
                       save: { await vm.setInternalComment(text.trimmed.isEmpty ? nil : text.trimmed) }) {
            Section {
                TextField("Internal note", text: $text, axis: .vertical).lineLimit(6...14).accessibilityIdentifier("order.note.text")
            } footer: { Text("Only your team can see this note.") }
        }.onAppear { vm.actionError = nil }
        #if os(macOS)
        .frame(width: 500, height: 380)
        #endif
    }
}

struct OrderTrackingSheet: View {
    @Bindable var vm: OrderDetailViewModel
    let delivery: OrderDelivery
    @State private var text: String
    private let original: String
    init(vm: OrderDetailViewModel, delivery: OrderDelivery) {
        self.vm = vm; self.delivery = delivery
        original = delivery.trackingCodes.joined(separator: "\n")
        _text = State(initialValue: original)
    }
    var body: some View {
        OrderFormSheet(title: "Tracking codes", canSave: vm.canEdit, busy: vm.busy, dirty: text != original, error: vm.actionError,
                       save: { await vm.setTrackingCodes(text.components(separatedBy: .newlines), deliveryId: delivery.id) }) {
            Section { Text(delivery.method).font(.headline) }
            Section {
                TextField("Tracking codes", text: $text, axis: .vertical).lineLimit(5...12)
                    .autocorrectionDisabled().accessibilityIdentifier("order.tracking.codes")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: { Text("Enter one tracking code per line.") }
        }.onAppear { vm.actionError = nil }
        #if os(macOS)
        .frame(width: 500, height: 400)
        #endif
    }
}
