import SwiftUI

/// Visual tone for state/status chips, mirroring the Android `stateTone`/`BadgeTone`.
enum BadgeTone {
    case done, inProgress, warning, error, neutral

    var color: Color {
        switch self {
        case .done: Theme.accent
        case .inProgress: Theme.tertiary
        case .warning: .orange
        case .error: .red
        case .neutral: .secondary
        }
    }
}

/// Maps a state machine technical name to a tone (mirrors the admin's state coloring).
func stateTone(_ technical: String) -> BadgeTone {
    switch technical {
    case "completed", "paid", "shipped", "done": .done
    case "cancelled", "failed", "refunded": .error
    case "in_progress", "open", "shipped_partially", "paid_partially": .inProgress
    default: .neutral
    }
}

/// A small pill showing a state name in its tone.
struct StatusBadge: View {
    let label: String
    let tone: BadgeTone

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.color.opacity(0.16), in: Capsule())
            .foregroundStyle(tone.color)
    }
}

/// +/-% change indicator.
struct DeltaBadge: View {
    let delta: Delta

    var body: some View {
        Label(delta.label, systemImage: delta.up ? "arrow.up.right" : "arrow.down.right")
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((delta.up ? Theme.accent : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(delta.up ? Theme.accent : .red)
    }
}

/// A rounded shop-tint icon box (used in the switcher and shop lists).
struct ShopIconBox: View {
    let tint: ShopTint
    var size: CGFloat = 42
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
            .fill(tint.bg(scheme == .dark))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "storefront")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(tint.fg(scheme == .dark))
            }
    }
}

/// A compact metric tile (icon + value + label).
struct StatTile: View {
    let symbol: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A section header with optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            accessory()
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title: title, accessory: { EmptyView() })
    }
}
