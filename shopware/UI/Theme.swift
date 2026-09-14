import SwiftUI

/// Shopware's core blue palette, adapted for native light and dark appearances.
/// Source: https://assets.shopware.com/media/website/press_materials/brochure/SW_CD_Design_Manual.pdf
enum Theme {
    /// Cyan brand color for artwork. Controls use the darker brand accent on light surfaces
    /// so small labels remain readable; the asset also colors system-provided controls.
    static let brand = Color(hex: 0x189EFF)
    static let accent = Color("AccentColor")
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x06325F)

    /// A soft tinted container for hero/accent surfaces.
    static let accentContainer = Color(light: 0xE3F3FF, dark: 0x06325F)
    static let onAccentContainer = Color(light: 0x06325F, dark: 0xE3F3FF)

    /// Neutral blue surfaces for setup cards and their backdrop.
    static let setupSurface = Color(light: 0xFFFFFF, dark: 0x192B3D)
    static let setupBackdrop = Color(light: 0xF3F8FC, dark: 0x101D2B)
}

extension View {
    /// The inset-grouped list look, resolved per platform (`.insetGrouped` on iOS, `.inset` on
    /// macOS where grouped isn't available). The app's standard Settings/Mail list style.
    func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// The grouped form look — consistent Settings-style sections across iOS and macOS sheets.
    func groupedFormStyle() -> some View {
        self.formStyle(.grouped)
    }
}

extension Color {
    /// Light/dark dynamic color from two 0xRRGGBB literals.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #else
        self.init(hex: light)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
