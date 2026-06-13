import SwiftUI

/// Per-shop pastel tint (precomputed from the original design's oklch values).
struct ShopTint: Equatable, Sendable {
    let lightBg: Color
    let lightFg: Color
    let darkBg: Color
    let darkFg: Color

    func bg(_ dark: Bool) -> Color { dark ? darkBg : lightBg }
    func fg(_ dark: Bool) -> Color { dark ? darkFg : lightFg }
}

enum PromoStatus: String, Codable, Equatable, Sendable {
    case active = "Active"
    case scheduled = "Scheduled"
    case ended = "Ended"
}

struct Delta: Equatable, Sendable {
    let pct: Int
    let up: Bool
    let label: String
}

/// The five pastel tints from the design, assignable to connected shops.
let TintPalette: [ShopTint] = [
    ShopTint(lightBg: Color(hex: 0xC3F3CE), lightFg: Color(hex: 0x034721),
             darkBg: Color(hex: 0x1E3A26), darkFg: Color(hex: 0xABE9BB)),
    ShopTint(lightBg: Color(hex: 0xDCEDB9), lightFg: Color(hex: 0x334100),
             darkBg: Color(hex: 0x2E3719), darkFg: Color(hex: 0xCDE19F)),
    ShopTint(lightBg: Color(hex: 0xF5E4B0), lightFg: Color(hex: 0x4B3800),
             darkBg: Color(hex: 0x3C3212), darkFg: Color(hex: 0xEDD692)),
    ShopTint(lightBg: Color(hex: 0xB0F5E8), lightFg: Color(hex: 0x00493E),
             darkBg: Color(hex: 0x0D3B35), darkFg: Color(hex: 0x91EBDC)),
    ShopTint(lightBg: Color(hex: 0xFFDBB5), lightFg: Color(hex: 0x5B2D00),
             darkBg: Color(hex: 0x452D16), darkFg: Color(hex: 0xFFCB9A)),
]

extension Color {
    /// Build a Color from a 0xRRGGBB literal (sRGB, opaque).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
