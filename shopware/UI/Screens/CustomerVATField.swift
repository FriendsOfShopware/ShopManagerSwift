import SwiftUI

/// Keeps separators while typing; the draft stores the normalized identifiers.
struct CustomerVATField: View {
    @Binding var values: [String]
    @State private var text = ""

    var body: some View {
        TextField("VAT IDs (comma separated)", text: $text)
            .autocorrectionDisabled()
            .onAppear { text = values.joined(separator: ", ") }
            .onChange(of: text) { values = text.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty } }
    }
}
