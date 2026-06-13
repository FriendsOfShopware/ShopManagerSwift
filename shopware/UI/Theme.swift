import SwiftUI

/// Forest accent palette + per-shop tint resolution. The Apple-HIG port keeps the Android app's
/// forest-green identity as the global tint, applied via `.tint(Theme.accent)`, and resolves the
/// five per-shop pastel tints for shop chrome.
enum Theme {
    /// Forest primary — fresh green. Used as the app accent (`.tint`).
    static let accent = Color(light: 0x1E6B3C, dark: 0x8BD6A4)

    /// A soft tinted container for hero/accent surfaces.
    static let accentContainer = Color(light: 0xA6F2BF, dark: 0x00522B)
    static let onAccentContainer = Color(light: 0x00210F, dark: 0xA6F2BF)

    /// Tertiary tone (used for in-progress states, info chips).
    static let tertiary = Color(light: 0x3A656F, dark: 0xA2CEDA)
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
