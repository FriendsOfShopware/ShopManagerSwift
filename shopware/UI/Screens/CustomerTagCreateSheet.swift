import SwiftUI
import ShopwareAdminAPI

struct CustomerTagCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let api: ShopApi
    let onCreated: (CustomerOption) -> Void
    @State private var name = ""
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag name", text: $name)
                if creating { ProgressView("Creating tag…") }
                if let error { Text(error).foregroundStyle(.red) }
            }.groupedFormStyle().disabled(creating)
                .navigationTitle("New tag")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(creating) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create tag", action: createTag).disabled(name.trimmed.isEmpty || creating)
                    }
                }
        }
        .interactiveDismissDisabled(creating)
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 180, idealHeight: 220)
        #endif
    }

    private func createTag() {
        guard !creating, !name.trimmed.isEmpty else { return }
        creating = true
        error = nil
        let tag = CustomerOption(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), name: name.trimmed)
        Task {
            defer { creating = false }
            do {
                try await api.repository("tag").create(.object(["id": .string(tag.id), "name": .string(tag.name)]))
                onCreated(tag)
                dismiss()
            } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
        }
    }
}
