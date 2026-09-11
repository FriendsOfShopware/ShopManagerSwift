import SwiftUI
import ShopwareAdminAPI

struct CustomerJSONField: View {
    let label: String
    @Binding var value: JSONValue?
    @State private var editing = false

    var body: some View {
        LabeledContent(label) {
            Button(value == nil || value == .null ? "Add data…" : "Edit data…") { editing = true }
        }
        .sheet(isPresented: $editing) {
            CustomerJSONEditSheet(label: label, value: value) { value = $0 }
        }
    }
}
