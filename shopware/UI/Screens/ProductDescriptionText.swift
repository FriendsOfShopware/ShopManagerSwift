import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ProductDescriptionText: View {
    let html: String
    @State private var text = AttributedString()
    var body: some View {
        Text(text).textSelection(.enabled)
            .task(id: html) {
                text = Self.formatted(html)
            }
    }

    static func formatted(_ html: String) -> AttributedString {
        let source = customerAttributedHTML(html)
        let native = NSAttributedString(source)
        var result = source
        for run in source.runs {
            var font = Font.body
            // NSFont is not Sendable. Read native attributes on the main actor
            // before replacing them with SwiftUI's adaptive body font.
            let range = NSRange(run.range, in: source)
            #if os(macOS)
            let traits = (native.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits
            if traits?.contains(.bold) == true { font = font.bold() }
            if traits?.contains(.italic) == true { font = font.italic() }
            #else
            let traits = (native.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits
            if traits?.contains(.traitBold) == true { font = font.bold() }
            if traits?.contains(.traitItalic) == true { font = font.italic() }
            #endif
            result[run.range].font = font
            result[run.range].foregroundColor = .primary
        }
        return result
    }
}
