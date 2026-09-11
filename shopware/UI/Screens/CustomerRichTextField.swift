#if os(macOS) || os(iOS)
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import ShopwareAdminAPI

struct CustomerRichTextField: View {
    let label: String
    @Binding var value: JSONValue?
    @State private var text = AttributedString()
    @State private var originalText = AttributedString()
    @State private var originalHTML = ""
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline)
            TextEditor(text: $text).frame(minHeight: 160)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .onAppear {
            guard !loaded else { return }
            originalHTML = value?.stringValue ?? ""
            originalText = customerAttributedHTML(originalHTML)
            text = originalText
            loaded = true
        }
        .onChange(of: text) {
            guard loaded else { return }
            if text == originalText {
                value = originalHTML.isEmpty ? .null : .string(originalHTML)
                return
            }
            do {
                let attributed = NSAttributedString(text)
                let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
                value = .string(String(decoding: data, as: UTF8.self))
                error = nil
            } catch { self.error = String(localized: "Couldn't update the formatted text.") }
        }
    }
}

func customerAttributedHTML(_ html: String) -> AttributedString {
    guard let attributed = try? NSAttributedString(data: Data(html.utf8), options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue,
    ], documentAttributes: nil) else { return AttributedString(html) }
    return AttributedString(attributed)
}
#endif
