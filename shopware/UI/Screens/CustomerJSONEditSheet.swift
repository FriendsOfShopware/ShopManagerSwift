import SwiftUI
import ShopwareAdminAPI

/// Apply is available only for valid JSON; cancel leaves the original custom field untouched.
struct CustomerJSONEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let label: String
    let onApply: (JSONValue) -> Void
    @State private var text: String

    init(label: String, value: JSONValue?, onApply: @escaping (JSONValue) -> Void) {
        self.label = label
        self.onApply = onApply
        let raw = (value ?? .null).encoded(sortedKeys: true)
        let object = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed])
        let data = object.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) } ?? raw
        _text = State(initialValue: String(decoding: data, as: UTF8.self))
    }

    private var parsed: JSONValue? { JSONValue.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit this field's structured data as JSON. Use null to clear it.").foregroundStyle(.secondary)
                TextEditor(text: $text).font(.body.monospaced()).autocorrectionDisabled()
                if parsed == nil { Label("Enter valid JSON before applying.", systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }.padding().navigationTitle(label)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { if let parsed { onApply(parsed); dismiss() } }.disabled(parsed == nil)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 600, minHeight: 360, idealHeight: 520)
        #endif
    }
}
