import SwiftUI

struct SetupWelcomeArtwork: View {
    var compact = false

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: compact ? 14 : 30) {
            ZStack {
                RoundedRectangle(cornerRadius: 40)
                    .fill(LinearGradient(colors: [Theme.accentContainer, Theme.accent.opacity(0.04)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .rotationEffect(.degrees(-8))
                Image(systemName: "storefront.fill")
                    .font(.system(size: compact ? 40 : 88, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.brand)
                if !compact {
                    symbolTile("shippingbox.fill", x: -94, y: 68)
                    symbolTile("chart.line.uptrend.xyaxis", x: 96, y: -66)
                }
            }
            .frame(width: compact ? 76 : 240, height: compact ? 76 : 220)
            .accessibilityHidden(true)
            VStack(alignment: compact ? .leading : .center, spacing: 12) {
                Text("Your shop. Wherever you are.")
                    .font(compact ? .title2.bold() : .largeTitle.bold())
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text("Orders, products, and customers.\nAll within reach.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Shopware")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .multilineTextAlignment(compact ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }

    private func symbolTile(_ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(Theme.accent)
            .frame(width: 60, height: 60)
            .background(Theme.setupSurface, in: .rect(cornerRadius: 18))
            .shadow(color: Theme.accent.opacity(0.1), radius: 12, y: 6)
            .offset(x: x, y: y)
    }
}

struct SetupProgress: View {
    let step: ConnectStep
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(ConnectStep.allCases) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.accent.opacity(0.12))
                        .frame(height: 3)
                    Text(item.title).font(.caption.weight(item == step ? .semibold : .regular))
                        .foregroundStyle(item == step ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of 3"))
        .accessibilityValue(Text(step.title))
        .accessibilityIdentifier("setup.progress")
    }
}

struct SetupShopPreview: View {
    let name: String
    let address: String
    let tintIndex: Int
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let tint = TintPalette[min(max(tintIndex, 0), TintPalette.count - 1)]
        HStack(spacing: 14) {
            Image(systemName: "storefront")
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(tint.fg(colorScheme == .dark).opacity(0.08), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name.isEmpty ? String(localized: "My Shop") : name)
                    .font(.headline).lineLimit(2)
                    .accessibilityIdentifier("setup.preview.name")
                Text(verbatim: URL(string: address)?.host() ?? address)
                    .font(.caption).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .foregroundStyle(tint.fg(colorScheme == .dark))
        .background(tint.bg(colorScheme == .dark), in: .rect(cornerRadius: 18))
    }
}

#Preview("Welcome artwork") {
    SetupWelcomeArtwork().padding(40).frame(width: 380).tint(Theme.accent)
}
