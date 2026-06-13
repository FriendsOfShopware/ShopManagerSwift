import SwiftUI

/// Visual tone for state/status, mirroring the Android `stateTone`. In the restrained Settings/Mail
/// language these drive a small colored dot + label, not a filled pill.
enum BadgeTone {
    case done, inProgress, warning, error, neutral

    var color: Color {
        switch self {
        case .done: Theme.accent
        case .inProgress: .blue
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

/// A state label preceded by a small tone dot — the restrained, system-native status indicator.
struct StatusBadge: View {
    let label: String
    let tone: BadgeTone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// +/-% change indicator — a tinted arrow + value, no filled background.
struct DeltaBadge: View {
    let delta: Delta

    var body: some View {
        Label(delta.label, systemImage: delta.up ? "arrow.up.right" : "arrow.down.right")
            .font(.subheadline.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(delta.up ? Theme.accent : .red)
    }
}

/// A small per-shop tint dot (replaces the large tinted icon box in the Settings/Mail language).
struct ShopTintDot: View {
    let tint: ShopTint
    var size: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(tint.bg(scheme == .dark))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
    }
}

/// A larger rounded shop-tint icon (kept for the connect/onboarding hero where an avatar reads well).
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

/// A metric as a native list row: leading symbol, title, and a bold trailing value.
/// Replaces the material `StatTile` card in the inset-grouped layout.
struct MetricRow: View {
    let symbol: String
    let label: LocalizedStringKey
    let value: String
    var tint: Color = Theme.accent

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .badge(Text(value).font(.body.weight(.semibold)).foregroundStyle(.primary))
    }
}
