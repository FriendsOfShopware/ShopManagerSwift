import SwiftUI
import ShopwareAdminAPI

struct CustomerColorField: View {
    @Environment(\.self) private var environment
    let label: String
    @Binding var value: JSONValue?

    var body: some View {
        HStack {
            ColorPicker(label, selection: Binding(get: { color }, set: { selected in
                let resolved = selected.resolve(in: environment)
                value = .string(String(format: "#%02x%02x%02x%02x", channel(resolved.red), channel(resolved.green), channel(resolved.blue), channel(resolved.opacity)))
            }))
            if value != nil && value != .null {
                Button("Clear", systemImage: "xmark.circle") { value = .null }.labelStyle(.iconOnly)
            }
        }
    }

    private func channel(_ value: Float) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }

    private var color: Color {
        var hex = (value?.stringValue ?? "000000").replacingOccurrences(of: "#", with: "")
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 6 { hex += "ff" }
        guard hex.count == 8, let rgba = UInt32(hex, radix: 16) else { return .black }
        return Color(.sRGB, red: Double((rgba >> 24) & 255) / 255, green: Double((rgba >> 16) & 255) / 255,
                     blue: Double((rgba >> 8) & 255) / 255, opacity: Double(rgba & 255) / 255)
    }
}
