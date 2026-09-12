import SwiftUI
import Testing
@testable import shopware

@MainActor
struct ProductDescriptionTests {
    @Test func formattingPreservesEmphasisAndLinksAfterUnicodeText() throws {
        let text = ProductDescriptionText.formatted("<p>🌿 Café <strong>linen</strong> <em>shirt</em> <strong><em>care</em></strong> <a href=\"https://shop.test/care\">guide</a></p>")
        #expect(String(text.characters).contains("🌿 Café linen shirt care guide"))
        let plain = try #require(text.range(of: "Café"))
        let bold = try #require(text.range(of: "linen"))
        let italic = try #require(text.range(of: "shirt"))
        let both = try #require(text.range(of: "care"))
        let link = try #require(text.range(of: "guide"))
        #expect(text[plain].font == Font.body)
        #expect(text[bold].font == Font.body.bold())
        #expect(text[italic].font == Font.body.italic())
        #expect(text[both].font == Font.body.bold().italic())
        #expect(text[link].link == URL(string: "https://shop.test/care"))
        #expect(text.runs.allSatisfy { $0.foregroundColor == Color.primary })
        #expect(ProductDescriptionText.formatted("").characters.isEmpty)
    }
}
